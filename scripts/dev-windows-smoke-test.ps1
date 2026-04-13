param(
  [switch]$UseRemoteDownload
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RootDir = Split-Path -Parent $PSScriptRoot
$LocalInstallPs1 = Join-Path $RootDir 'install.ps1'
$RemoteInstallPs1Url = 'https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1'

function Write-Log {
  param([string]$Message)
  Write-Host "[win-smoke] $Message"
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Path {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    throw "Missing path: $Path"
  }
}

function Assert-FileContains {
  param(
    [string]$Path,
    [string]$Needle
  )

  Assert-Path $Path
  if (-not (Select-String -Path $Path -SimpleMatch -Pattern $Needle -Quiet)) {
    throw "File $Path did not contain expected text: $Needle"
  }
}

function Assert-FileNotContains {
  param(
    [string]$Path,
    [string]$Needle
  )

  Assert-Path $Path
  if (Select-String -Path $Path -SimpleMatch -Pattern $Needle -Quiet) {
    throw "File $Path unexpectedly contained text: $Needle"
  }
}

function Wait-Until {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$FailureMessage,

    [int]$TimeoutSeconds = 20,
    [int]$IntervalMilliseconds = 250
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }
    Start-Sleep -Milliseconds $IntervalMilliseconds
  }

  throw $FailureMessage
}

function Merge-Hashtable {
  param(
    [hashtable]$Base,
    [hashtable]$Extra
  )

  $merged = @{}
  foreach ($key in $Base.Keys) {
    $merged[$key] = $Base[$key]
  }
  foreach ($key in $Extra.Keys) {
    $merged[$key] = $Extra[$key]
  }
  return $merged
}

function Invoke-ExternalProcess {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [string]$WorkingDirectory = $RootDir,
    [hashtable]$Environment = @{},
    [int[]]$AllowedExitCodes = @(0)
  )

  $stdoutFile = Join-Path ([IO.Path]::GetTempPath()) ("ai-cli-sync-stdout-" + [guid]::NewGuid().ToString('N') + ".log")
  $stderrFile = Join-Path ([IO.Path]::GetTempPath()) ("ai-cli-sync-stderr-" + [guid]::NewGuid().ToString('N') + ".log")
  $savedEnvironment = @{}

  try {
    foreach ($key in $Environment.Keys) {
      $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
      [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }

    $startProcessArgs = @{
      FilePath               = $FilePath
      ArgumentList           = $ArgumentList
      WorkingDirectory       = $WorkingDirectory
      NoNewWindow            = $true
      PassThru               = $true
      Wait                   = $true
      RedirectStandardOutput = $stdoutFile
      RedirectStandardError  = $stderrFile
    }

    $process = Start-Process @startProcessArgs
    $stdout = if (Test-Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { '' }
    if ($null -eq $stdout) {
      $stdout = ''
    }

    $stderr = if (Test-Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { '' }
    if ($null -eq $stderr) {
      $stderr = ''
    }

    if ($AllowedExitCodes -notcontains $process.ExitCode) {
      throw "Command failed: $FilePath $($ArgumentList -join ' ')`nExitCode: $($process.ExitCode)`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
    }

    return [pscustomobject]@{
      ExitCode = $process.ExitCode
      StdOut   = $stdout
      StdErr   = $stderr
    }
  }
  finally {
    foreach ($key in $savedEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }

    Remove-Item -Path $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-Git {
  param(
    [string[]]$Arguments,
    [string]$WorkingDirectory = $RootDir
  )

  $result = Invoke-ExternalProcess -FilePath 'git' -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory
  return ([string]$result.StdOut).Trim()
}

function New-TestContext {
  param([string]$Name)

  $baseDir = Join-Path ([IO.Path]::GetTempPath()) ("ai-cli-sync-win-" + $Name + "-" + [guid]::NewGuid().ToString('N'))
  $homeDir = Join-Path $baseDir 'home'
  $tempDir = Join-Path $baseDir 'temp'
  $fakeBinDir = Join-Path $baseDir 'fakebin'

  New-Item -ItemType Directory -Path $baseDir, $homeDir, $tempDir, $fakeBinDir -Force | Out-Null

  return [pscustomobject]@{
    BaseDir    = $baseDir
    HomeDir    = $homeDir
    TempDir    = $tempDir
    FakeBinDir = $fakeBinDir
    Env        = @{
      USERPROFILE = $homeDir
      HOME        = $homeDir
      TEMP        = $tempDir
      TMP         = $tempDir
    }
  }
}

function Remove-TestContext {
  param($Context)
  if ($null -ne $Context -and (Test-Path $Context.BaseDir)) {
    Remove-Item -Path $Context.BaseDir -Recurse -Force
  }
}

function Get-PathWithoutPython {
  param([string]$PathValue = $env:PATH)

  $parts = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $filtered = foreach ($part in $parts) {
    $candidate = $part.Trim('"')
    if (-not (Test-Path $candidate)) {
      $part
      continue
    }

    $hasPython = $false
    foreach ($name in @('python.exe', 'python3.exe', 'py.exe', 'python.bat', 'python3.bat', 'py.bat', 'python.cmd', 'python3.cmd', 'py.cmd')) {
      if (Test-Path (Join-Path $candidate $name)) {
        $hasPython = $true
        break
      }
    }

    if (-not $hasPython) {
      $part
    }
  }

  return ($filtered -join ';')
}

function Get-DownloadedInstallPowerShellScript {
  param($Context)

  $downloadedInstallPath = Join-Path $Context.TempDir 'ai-cli-config-sync-install.ps1'
  $escapedDownloadedInstallPath = $downloadedInstallPath.Replace("'", "''")

  $downloadLine = if ($UseRemoteDownload) {
    "Invoke-WebRequest -UseBasicParsing '$RemoteInstallPs1Url' -OutFile `$downloadedInstallPath"
  } else {
    $escapedInstallPath = $LocalInstallPs1.Replace("'", "''")
    "Copy-Item -Path '$escapedInstallPath' -Destination `$downloadedInstallPath -Force"
  }

  return @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$downloadedInstallPath = '$escapedDownloadedInstallPath'
Remove-Item -Path `$downloadedInstallPath -Force -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
$(if ($UseRemoteDownload) { '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12' })
$downloadLine
if (-not (Test-Path `$downloadedInstallPath)) { throw 'Failed to stage install.ps1' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls
& `$downloadedInstallPath
"@
}

function Get-DownloadedInstallCmdLine {
  if ($UseRemoteDownload) {
    return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing ''https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1'' -OutFile ''%AI_CLI_SYNC_INSTALL_PS1%''"'
  }

  $escapedInstallPath = $LocalInstallPs1.Replace("'", "''")
  return "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""Copy-Item -Path '$escapedInstallPath' -Destination '%AI_CLI_SYNC_INSTALL_PS1%' -Force"""
}

function Get-DownloadedInstallCmdRunLine {
  return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls; & ''%AI_CLI_SYNC_INSTALL_PS1%''"'
}

function Test-ReadmeWindowsInstallDocs {
  Write-Log '验证 README 的 Windows 安装命令包含 TLS 1.2 与失败保护'

  foreach ($path in @(
    (Join-Path $RootDir 'README.md'),
    (Join-Path $RootDir 'README_EN.md')
  )) {
    Assert-FileContains -Path $path -Needle 'Tls12'
    Assert-FileContains -Path $path -Needle 'Remove-Item -Path $tmp'
    Assert-FileContains -Path $path -Needle 'if (-not (Test-Path $tmp))'
    Assert-FileContains -Path $path -Needle 'del /f /q "%AI_CLI_SYNC_INSTALL_PS1%"'
    Assert-FileContains -Path $path -Needle 'if not exist "%AI_CLI_SYNC_INSTALL_PS1%"'
  }
}

function Assert-InstalledScripts {
  param($Context)

  foreach ($relativePath in @(
    '.cli-sync\install.ps1',
    '.cli-sync\setup.ps1',
    '.cli-sync\push.ps1',
    '.cli-sync\pull.ps1',
    '.cli-sync\sync.ps1',
    '.cli-sync\status.ps1',
    '.cli-sync\enable-auto-sync.ps1',
    '.cli-sync\runtime.ps1',
    '.claude\skills\ai-cli-config-sync\SKILL.md',
    '.codex\skills\ai-cli-config-sync\SKILL.md'
  )) {
    Assert-Path (Join-Path $Context.HomeDir $relativePath)
  }
}

function Install-WithLocalPs1 {
  param($Context)

  Invoke-ExternalProcess -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $LocalInstallPs1
  ) -WorkingDirectory $RootDir -Environment $Context.Env | Out-Null

  Assert-InstalledScripts $Context
}

function Install-WithDownloadedPowerShell {
  param($Context)

  $bootstrapScript = Join-Path $Context.BaseDir 'download-install.ps1'
  Set-Content -Path $bootstrapScript -Value (Get-DownloadedInstallPowerShellScript -Context $Context) -Encoding ascii

  $environment = $Context.Env
  if (-not $UseRemoteDownload) {
    $environment = Merge-Hashtable -Base $environment -Extra @{
      AI_CLI_SYNC_INSTALL_SOURCE_DIR = $RootDir
    }
  }

  Invoke-ExternalProcess -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $bootstrapScript
  ) -WorkingDirectory $RootDir -Environment $environment | Out-Null

  Assert-InstalledScripts $Context
}

function Install-WithLocalPs1FromCmd {
  param($Context)

  $cmdFile = Join-Path $Context.BaseDir 'local-install.cmd'
  $escapedRepoInstallPath = $LocalInstallPs1.Replace('"', '""')
  $cmdContent = @"
@echo off
set "USERPROFILE=$($Context.HomeDir)"
set "HOME=$($Context.HomeDir)"
set "TEMP=$($Context.TempDir)"
set "TMP=$($Context.TempDir)"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$escapedRepoInstallPath"
"@
  Set-Content -Path $cmdFile -Value $cmdContent -Encoding ascii

  Invoke-ExternalProcess -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $cmdFile) -WorkingDirectory $RootDir | Out-Null
  Assert-InstalledScripts $Context
}

function Install-WithDownloadedCmd {
  param($Context)

  $cmdFile = Join-Path $Context.BaseDir 'download-install.cmd'
  $downloadLine = Get-DownloadedInstallCmdLine
  $runLine = Get-DownloadedInstallCmdRunLine
  $cmdContent = @"
@echo off
set "USERPROFILE=$($Context.HomeDir)"
set "HOME=$($Context.HomeDir)"
set "TEMP=$($Context.TempDir)"
set "TMP=$($Context.TempDir)"
$(if (-not $UseRemoteDownload) { 'set "AI_CLI_SYNC_INSTALL_SOURCE_DIR=' + $RootDir + '"' })
set "AI_CLI_SYNC_INSTALL_PS1=%TEMP%\ai-cli-config-sync-install.ps1"
if exist "%AI_CLI_SYNC_INSTALL_PS1%" del /f /q "%AI_CLI_SYNC_INSTALL_PS1%"
$downloadLine
if errorlevel 1 exit /b 1
if not exist "%AI_CLI_SYNC_INSTALL_PS1%" exit /b 1
$runLine
"@
  Set-Content -Path $cmdFile -Value $cmdContent -Encoding ascii

  Invoke-ExternalProcess -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $cmdFile) -WorkingDirectory $RootDir | Out-Null
  Assert-InstalledScripts $Context
}

function New-BrokenPythonShims {
  param($Context)

  foreach ($name in @('python3.cmd', 'python.cmd', 'py.cmd')) {
    $shimPath = Join-Path $Context.FakeBinDir $name
    Set-Content -Path $shimPath -Value "@echo off`r`nexit /b 49`r`n" -Encoding ascii
  }
}

function New-BareRemoteRepo {
  param(
    [string]$RemotePath,
    [hashtable]$Files = @{}
  )

  Invoke-Git -Arguments @('init', '--bare', $RemotePath) | Out-Null
  Invoke-Git -Arguments @("--git-dir=$RemotePath", 'symbolic-ref', 'HEAD', 'refs/heads/main') | Out-Null

  if ($Files.Count -eq 0) {
    return
  }

  $sourceDir = Join-Path (Split-Path -Parent $RemotePath) ("seed-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

  try {
    Invoke-Git -Arguments @('init', $sourceDir) | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'config', 'user.name', 'smoke-test') | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'config', 'user.email', 'smoke@example.com') | Out-Null

    foreach ($relativePath in $Files.Keys) {
      $fullPath = Join-Path $sourceDir $relativePath
      $parentDir = Split-Path -Parent $fullPath
      if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
      }
      Set-Content -Path $fullPath -Value $Files[$relativePath] -Encoding utf8
    }

    Invoke-Git -Arguments @('-C', $sourceDir, 'add', '.') | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'commit', '-m', 'seed') | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'branch', '-M', 'main') | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'remote', 'add', 'origin', $RemotePath) | Out-Null
    Invoke-Git -Arguments @('-C', $sourceDir, 'push', 'origin', 'main') | Out-Null
    Invoke-Git -Arguments @("--git-dir=$RemotePath", 'symbolic-ref', 'HEAD', 'refs/heads/main') | Out-Null
  }
  finally {
    Remove-Item -Path $sourceDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Initialize-LocalSyncRepo {
  param(
    $Context,
    [string]$RemotePath
  )

  $syncRepoDir = Join-Path $Context.HomeDir '.cli-sync-repo'
  Invoke-Git -Arguments @('init', $syncRepoDir) | Out-Null
  Invoke-Git -Arguments @('-C', $syncRepoDir, 'checkout', '-b', 'main') | Out-Null
  Invoke-Git -Arguments @('-C', $syncRepoDir, 'remote', 'add', 'origin', $RemotePath) | Out-Null
  Invoke-Git -Arguments @('-C', $syncRepoDir, 'config', 'user.name', 'smoke-test') | Out-Null
  Invoke-Git -Arguments @('-C', $syncRepoDir, 'config', 'user.email', 'smoke@example.com') | Out-Null
}

function Write-SyncConfig {
  param(
    $Context,
    [string]$RemotePath
  )

  $configPath = Join-Path $Context.HomeDir '.cli-sync\config.yml'
  Set-Content -Path $configPath -Value @"
remote: $RemotePath
branch: main
auto_pull: false
auto_push: false
"@ -Encoding ascii
}

function Invoke-WindowsWrapper {
  param(
    $Context,
    [ValidateSet('powershell', 'cmd')]
    [string]$Launcher,
    [string]$ScriptName,
    [string[]]$Arguments = @(),
    [hashtable]$ExtraEnvironment = @{}
  )

  $environment = Merge-Hashtable -Base $Context.Env -Extra $ExtraEnvironment
  $scriptPath = Join-Path $Context.HomeDir ".cli-sync\$ScriptName"

  if ($Launcher -eq 'powershell') {
    return Invoke-ExternalProcess -FilePath 'powershell.exe' -ArgumentList (@(
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', $scriptPath
    ) + $Arguments) -Environment $environment
  }

  $cmdFile = Join-Path $Context.BaseDir ("invoke-" + $ScriptName + "-" + [guid]::NewGuid().ToString('N') + ".cmd")
  $quotedArgs = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ' '
  $cmdContent = @"
@echo off
set "USERPROFILE=$($Context.HomeDir)"
set "HOME=$($Context.HomeDir)"
set "TEMP=$($Context.TempDir)"
set "TMP=$($Context.TempDir)"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scriptPath" $quotedArgs
"@
  Set-Content -Path $cmdFile -Value $cmdContent -Encoding ascii
  return Invoke-ExternalProcess -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $cmdFile) -Environment $environment
}

function Test-InstallMethods {
  Write-Log "验证 clone 后运行 install.ps1（PowerShell）"
  $testCtx = $null
  $testCtx = New-TestContext 'install-local-ps'
  try {
    Install-WithLocalPs1 $testCtx
  }
  finally {
    Remove-TestContext $testCtx
  }

  Write-Log "验证 clone 后运行 install.ps1（cmd）"
  $testCtx = $null
  $testCtx = New-TestContext 'install-local-cmd'
  try {
    Install-WithLocalPs1FromCmd $testCtx
  }
  finally {
    Remove-TestContext $testCtx
  }

  Write-Log "验证下载 install.ps1 后执行（PowerShell）"
  $testCtx = $null
  $testCtx = New-TestContext 'install-download-ps'
  try {
    Install-WithDownloadedPowerShell $testCtx
  }
  finally {
    Remove-TestContext $testCtx
  }

  Write-Log "验证下载 install.ps1 后执行（cmd）"
  $testCtx = $null
  $testCtx = New-TestContext 'install-download-cmd'
  try {
    Install-WithDownloadedCmd $testCtx
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-SetupPrefersPull {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 setup.ps1 在已有本地同步仓库时仍会优先拉取远端（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("setup-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx
    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath -Files @{
      'codex/AGENTS.md' = "# remote`nsetup pull wins`n"
    }
    Invoke-Git -Arguments @('clone', $remotePath, (Join-Path $testCtx.HomeDir '.cli-sync-repo')) | Out-Null

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'setup.ps1' -Arguments @('-RemoteUrl', $remotePath) | Out-Null

    Assert-FileContains -Path (Join-Path $testCtx.HomeDir '.codex\AGENTS.md') -Needle 'setup pull wins'
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-PushNodeFallback {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 push.ps1 在 Python 不可用时会回退到 node（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("push-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx
    New-BrokenPythonShims $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath
    Initialize-LocalSyncRepo -Context $testCtx -RemotePath $remotePath
    Write-SyncConfig -Context $testCtx -RemotePath $remotePath

    $copilotDir = Join-Path $testCtx.HomeDir '.copilot'
    New-Item -ItemType Directory -Path $copilotDir -Force | Out-Null
    Set-Content -Path (Join-Path $copilotDir 'config.json') -Value @'
{
  "banner": {
    "hidden": true
  },
  "model": "gpt-5",
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  }
}
'@ -Encoding utf8
    Set-Content -Path (Join-Path $copilotDir 'mcp-config.json') -Value @'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"],
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    }
  }
}
'@ -Encoding utf8

    $extraEnv = @{
      PATH = $testCtx.FakeBinDir + ';' + (Get-PathWithoutPython)
    }
    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'push.ps1' -ExtraEnvironment $extraEnv | Out-Null

    Assert-FileContains -Path (Join-Path $testCtx.HomeDir '.cli-sync-repo\copilot\config.json') -Needle '"model": "gpt-5"'
    Assert-FileNotContains -Path (Join-Path $testCtx.HomeDir '.cli-sync-repo\copilot\config.json') -Needle 'copilot_tokens'
    Assert-FileNotContains -Path (Join-Path $testCtx.HomeDir '.cli-sync-repo\copilot\mcp-config.json') -Needle '"env"'
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-PullNodeFallback {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 pull.ps1 在 Python 不可用时会回退到 node（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("pull-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx
    New-BrokenPythonShims $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath -Files @{
      'copilot/config.json' = @'
{
  "banner": {
    "hidden": false
  },
  "model": "gpt-5"
}
'@
      'copilot/mcp-config.json' = @'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"]
    }
  }
}
'@
    }

    Invoke-Git -Arguments @('clone', $remotePath, (Join-Path $testCtx.HomeDir '.cli-sync-repo')) | Out-Null
    Write-SyncConfig -Context $testCtx -RemotePath $remotePath

    $copilotDir = Join-Path $testCtx.HomeDir '.copilot'
    New-Item -ItemType Directory -Path $copilotDir -Force | Out-Null
    Set-Content -Path (Join-Path $copilotDir 'config.json') -Value @'
{
  "firstLaunchAt": "2026-01-01T00:00:00Z",
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  },
  "trusted_folders": [
    "/tmp/project"
  ]
}
'@ -Encoding utf8
    Set-Content -Path (Join-Path $copilotDir 'mcp-config.json') -Value @'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "old-command",
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    },
    "local-only": {
      "command": "keep-local",
      "env": {
        "LOCAL_ONLY": "1"
      }
    }
  }
}
'@ -Encoding utf8

    $extraEnv = @{
      PATH = $testCtx.FakeBinDir + ';' + (Get-PathWithoutPython)
    }
    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'pull.ps1' -ExtraEnvironment $extraEnv | Out-Null

    Assert-FileContains -Path (Join-Path $copilotDir 'config.json') -Needle '"model": "gpt-5"'
    Assert-FileContains -Path (Join-Path $copilotDir 'config.json') -Needle 'copilot_tokens'
    Assert-FileContains -Path (Join-Path $copilotDir 'mcp-config.json') -Needle '"command": "uvx"'
    Assert-FileContains -Path (Join-Path $copilotDir 'mcp-config.json') -Needle '"UV_HTTP_TIMEOUT": "120"'
    Assert-FileContains -Path (Join-Path $copilotDir 'mcp-config.json') -Needle 'LOCAL_ONLY'
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-StatusNoFalsePositive {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 status.ps1 在 CRLF 差异和 Python 不可用时不会误报（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("status-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx
    New-BrokenPythonShims $testCtx

    $repoDir = Join-Path $testCtx.HomeDir '.cli-sync-repo'
    Invoke-Git -Arguments @('init', $repoDir) | Out-Null
    Invoke-Git -Arguments @('-C', $repoDir, 'config', 'user.name', 'smoke-test') | Out-Null
    Invoke-Git -Arguments @('-C', $repoDir, 'config', 'user.email', 'smoke@example.com') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repoDir 'copilot') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $repoDir 'copilot\copilot-instructions.md'), "# Shared`n")
    [IO.File]::WriteAllText((Join-Path $repoDir 'copilot\config.json'), "{`n  `"model`": `"gpt-5`"`n}`n")
    Invoke-Git -Arguments @('-C', $repoDir, 'add', 'copilot') | Out-Null
    Invoke-Git -Arguments @('-C', $repoDir, 'commit', '-m', 'init') | Out-Null

    $copilotDir = Join-Path $testCtx.HomeDir '.copilot'
    New-Item -ItemType Directory -Path $copilotDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $copilotDir 'copilot-instructions.md'), "# Shared`r`n")
    [IO.File]::WriteAllText((Join-Path $copilotDir 'config.json'), "{`r`n  `"model`": `"gpt-5`"`r`n}`r`n")

    $extraEnv = @{
      PATH = $testCtx.FakeBinDir + ';' + (Get-PathWithoutPython)
    }
    $result = Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'status.ps1' -ExtraEnvironment $extraEnv

    Assert-True -Condition ($result.StdOut -notlike '*copilot/config.json*') -Message 'status.ps1 should not report copilot/config.json as changed'
    Assert-True -Condition ($result.StdOut -notlike '*copilot-instructions.md*') -Message 'status.ps1 should not report copilot-instructions.md as changed'
    Assert-True -Condition ($result.StdOut -notlike '*有本地未推送*') -Message 'status.ps1 should not report false local changes'
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-SyncPushes {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 sync.ps1 会优先推送本地配置（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("sync-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath
    Initialize-LocalSyncRepo -Context $testCtx -RemotePath $remotePath
    Write-SyncConfig -Context $testCtx -RemotePath $remotePath

    $codexDir = Join-Path $testCtx.HomeDir '.codex'
    New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
    Set-Content -Path (Join-Path $codexDir 'AGENTS.md') -Value "# sync from $Launcher`n" -Encoding utf8

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'sync.ps1' | Out-Null

    $remoteDump = Join-Path $testCtx.BaseDir 'remote-dump'
    Invoke-Git -Arguments @('clone', $remotePath, $remoteDump) | Out-Null
    Assert-FileContains -Path (Join-Path $remoteDump 'codex\AGENTS.md') -Needle "sync from $Launcher"
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Get-ProfilePathForContext {
  param($Context)
  $result = Invoke-ExternalProcess -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Command', '$PROFILE') -Environment $Context.Env
  $profilePath = ([string]$result.StdOut).Trim()
  if ([string]::IsNullOrWhiteSpace($profilePath)) {
    return Join-Path $Context.HomeDir 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
  }
  return $profilePath
}

function Invoke-ProfiledPowerShellScript {
  param(
    $Context,
    [string]$ScriptPath
  )

  return Invoke-ExternalProcess -FilePath 'powershell.exe' -ArgumentList @(
    '-ExecutionPolicy', 'Bypass',
    '-File', $ScriptPath
  ) -Environment $Context.Env
}

function Test-AutoPullOnPowerShellStartup {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 auto_pull=true 时 PowerShell 启动会自动拉取（enable-auto-sync 通过 $Launcher 调用）"
  $testCtx = $null
  $testCtx = New-TestContext ("auto-pull-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath -Files @{
      'codex/AGENTS.md' = "# remote`nauto pull works`n"
    }
    Invoke-Git -Arguments @('clone', $remotePath, (Join-Path $testCtx.HomeDir '.cli-sync-repo')) | Out-Null
    Invoke-Git -Arguments @('-C', (Join-Path $testCtx.HomeDir '.cli-sync-repo'), 'config', 'user.name', 'smoke-test') | Out-Null
    Invoke-Git -Arguments @('-C', (Join-Path $testCtx.HomeDir '.cli-sync-repo'), 'config', 'user.email', 'smoke@example.com') | Out-Null
    Write-SyncConfig -Context $testCtx -RemotePath $remotePath

    $configPath = Join-Path $testCtx.HomeDir '.cli-sync\config.yml'
    Set-Content -Path $configPath -Value @"
remote: $remotePath
branch: main
auto_pull: true
auto_push: false
"@ -Encoding ascii

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    $pulledAgentsPath = Join-Path $testCtx.HomeDir '.codex\AGENTS.md'
    Remove-Item -Path $pulledAgentsPath -Force -ErrorAction SilentlyContinue

    $sessionScript = Join-Path $testCtx.BaseDir 'auto-pull-session.ps1'
    Set-Content -Path $sessionScript -Value 'Start-Sleep -Seconds 3' -Encoding ascii
    Invoke-ProfiledPowerShellScript -Context $testCtx -ScriptPath $sessionScript | Out-Null

    Wait-Until -FailureMessage 'PowerShell startup did not auto-pull codex/AGENTS.md' -Condition {
      (Test-Path $pulledAgentsPath) -and ((Get-Content -Path $pulledAgentsPath -Raw) -like '*auto pull works*')
    }

    Assert-FileContains -Path $pulledAgentsPath -Needle 'auto pull works'
    $logPath = Join-Path $testCtx.HomeDir '.cli-sync\auto-sync.log'
    Wait-Until -FailureMessage 'Windows auto-sync log did not record the startup pull' -Condition {
      (Test-Path $logPath) -and (Select-String -Path $logPath -SimpleMatch -Pattern '从远程拉取配置' -Quiet)
    }
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-AutoPushOnPowerShellExit {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 auto_push=true 时 PowerShell 退出会自动推送（enable-auto-sync 通过 $Launcher 调用）"
  $testCtx = $null
  $testCtx = New-TestContext ("auto-push-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath
    Initialize-LocalSyncRepo -Context $testCtx -RemotePath $remotePath
    Write-SyncConfig -Context $testCtx -RemotePath $remotePath

    $configPath = Join-Path $testCtx.HomeDir '.cli-sync\config.yml'
    Set-Content -Path $configPath -Value @"
remote: $remotePath
branch: main
auto_pull: false
auto_push: true
"@ -Encoding ascii

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    $sessionScript = Join-Path $testCtx.BaseDir 'auto-push-session.ps1'
    Set-Content -Path $sessionScript -Value @'
$codexDir = Join-Path $HOME ".codex"
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
Set-Content -Path (Join-Path $codexDir "AGENTS.md") -Value "# local`nauto push works`n" -Encoding utf8
'@ -Encoding ascii
    Invoke-ProfiledPowerShellScript -Context $testCtx -ScriptPath $sessionScript | Out-Null

    $remoteDump = Join-Path $testCtx.BaseDir 'remote-dump'
    Wait-Until -FailureMessage 'PowerShell exit did not auto-push codex/AGENTS.md' -Condition {
      Remove-Item -Path $remoteDump -Recurse -Force -ErrorAction SilentlyContinue
      try {
        Invoke-Git -Arguments @('clone', $remotePath, $remoteDump) | Out-Null
        return (Test-Path (Join-Path $remoteDump 'codex\AGENTS.md')) -and ((Get-Content -Path (Join-Path $remoteDump 'codex\AGENTS.md') -Raw) -like '*auto push works*')
      }
      catch {
        return $false
      }
    }

    Remove-Item -Path $remoteDump -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-Git -Arguments @('clone', $remotePath, $remoteDump) | Out-Null
    Assert-FileContains -Path (Join-Path $remoteDump 'codex\AGENTS.md') -Needle 'auto push works'

    $logPath = Join-Path $testCtx.HomeDir '.cli-sync\auto-sync.log'
    Wait-Until -FailureMessage 'Windows auto-sync log did not record the exit push' -Condition {
      (Test-Path $logPath) -and (Select-String -Path $logPath -SimpleMatch -Pattern '配置已推送' -Quiet)
    }
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-AutoPullDisabled {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 auto_pull=false 时 PowerShell 启动不会自动拉取（enable-auto-sync 通过 $Launcher 调用）"
  $testCtx = $null
  $testCtx = New-TestContext ("auto-pull-disabled-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath -Files @{
      'codex/AGENTS.md' = "# remote`nshould not auto pull`n"
    }
    Invoke-Git -Arguments @('clone', $remotePath, (Join-Path $testCtx.HomeDir '.cli-sync-repo')) | Out-Null
    Invoke-Git -Arguments @('-C', (Join-Path $testCtx.HomeDir '.cli-sync-repo'), 'config', 'user.name', 'smoke-test') | Out-Null
    Invoke-Git -Arguments @('-C', (Join-Path $testCtx.HomeDir '.cli-sync-repo'), 'config', 'user.email', 'smoke@example.com') | Out-Null

    Set-Content -Path (Join-Path $testCtx.HomeDir '.cli-sync\config.yml') -Value @"
remote: $remotePath
branch: main
auto_pull: false
auto_push: false
"@ -Encoding ascii

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    $pulledAgentsPath = Join-Path $testCtx.HomeDir '.codex\AGENTS.md'
    Remove-Item -Path $pulledAgentsPath -Force -ErrorAction SilentlyContinue

    $sessionScript = Join-Path $testCtx.BaseDir 'auto-pull-disabled-session.ps1'
    Set-Content -Path $sessionScript -Value 'Start-Sleep -Seconds 3' -Encoding ascii
    Invoke-ProfiledPowerShellScript -Context $testCtx -ScriptPath $sessionScript | Out-Null
    Start-Sleep -Seconds 2

    Assert-True -Condition (-not (Test-Path $pulledAgentsPath)) -Message 'auto_pull=false should not pull codex/AGENTS.md on PowerShell startup'
    $logPath = Join-Path $testCtx.HomeDir '.cli-sync\auto-sync.log'
    if (Test-Path $logPath) {
      Assert-FileNotContains -Path $logPath -Needle '从远程拉取配置'
    }
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-AutoPushDisabled {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 auto_push=false 时 PowerShell 退出不会自动推送（enable-auto-sync 通过 $Launcher 调用）"
  $testCtx = $null
  $testCtx = New-TestContext ("auto-push-disabled-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    $remotePath = Join-Path $testCtx.BaseDir 'remote.git'
    New-BareRemoteRepo -RemotePath $remotePath
    Initialize-LocalSyncRepo -Context $testCtx -RemotePath $remotePath

    Set-Content -Path (Join-Path $testCtx.HomeDir '.cli-sync\config.yml') -Value @"
remote: $remotePath
branch: main
auto_pull: false
auto_push: false
"@ -Encoding ascii

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    $sessionScript = Join-Path $testCtx.BaseDir 'auto-push-disabled-session.ps1'
    Set-Content -Path $sessionScript -Value @'
$codexDir = Join-Path $HOME ".codex"
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
Set-Content -Path (Join-Path $codexDir "AGENTS.md") -Value "# local`nshould not auto push`n" -Encoding utf8
'@ -Encoding ascii
    Invoke-ProfiledPowerShellScript -Context $testCtx -ScriptPath $sessionScript | Out-Null
    Start-Sleep -Seconds 2

    $remoteHead = Invoke-ExternalProcess -FilePath 'git' -ArgumentList @("--git-dir=$remotePath", 'branch', '--list', 'main')
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($remoteHead.StdOut)) -Message 'auto_push=false should not create a pushed commit on refs/heads/main'

    $logPath = Join-Path $testCtx.HomeDir '.cli-sync\auto-sync.log'
    if (Test-Path $logPath) {
      Assert-FileNotContains -Path $logPath -Needle '配置已推送'
    }
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Test-EnableAutoSync {
  param([ValidateSet('powershell', 'cmd')][string]$Launcher)

  Write-Log "验证 enable-auto-sync.ps1 会写入 PowerShell profile（$Launcher）"
  $testCtx = $null
  $testCtx = New-TestContext ("auto-sync-" + $Launcher)
  try {
    Install-WithLocalPs1 $testCtx

    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    $profilePath = Get-ProfilePathForContext -Context $testCtx
    Assert-Path $profilePath
    Assert-FileContains -Path $profilePath -Needle 'ai-cli-config-sync-hook-start'
    Assert-FileContains -Path $profilePath -Needle 'Register-EngineEvent -SourceIdentifier PowerShell.Exiting'

    Set-Content -Path $profilePath -Value @'
# >>> ai-cli-config-sync-hook-start >>>
old windows hook
# <<< ai-cli-config-sync-hook-end <<<
'@ -Encoding utf8
    Invoke-WindowsWrapper -Context $testCtx -Launcher $Launcher -ScriptName 'enable-auto-sync.ps1' | Out-Null

    Assert-FileContains -Path $profilePath -Needle 'Register-EngineEvent -SourceIdentifier PowerShell.Exiting'
    Assert-FileNotContains -Path $profilePath -Needle 'old windows hook'
  }
  finally {
    Remove-TestContext $testCtx
  }
}

function Main {
  Test-ReadmeWindowsInstallDocs
  Test-InstallMethods
  foreach ($launcher in @('powershell', 'cmd')) {
    Test-SetupPrefersPull -Launcher $launcher
    Test-PushNodeFallback -Launcher $launcher
    Test-PullNodeFallback -Launcher $launcher
    Test-StatusNoFalsePositive -Launcher $launcher
    Test-SyncPushes -Launcher $launcher
    Test-EnableAutoSync -Launcher $launcher
    Test-AutoPullOnPowerShellStartup -Launcher $launcher
    Test-AutoPushOnPowerShellExit -Launcher $launcher
    Test-AutoPullDisabled -Launcher $launcher
    Test-AutoPushDisabled -Launcher $launcher
  }
  Write-Log '✅ 所有 Windows smoke test 通过'
}

Main
