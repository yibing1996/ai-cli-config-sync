Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PayloadPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BasePath,

    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  return Join-Path $BasePath ($RelativePath -replace '/', '\')
}

function Enable-Tls12ForDownloads {
  $tls12 = [Net.SecurityProtocolType]::Tls12
  if (([Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $tls12
  }
}

function Invoke-DownloadFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $destinationDir = Split-Path -Parent $DestinationPath
  if ($destinationDir) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Enable-Tls12ForDownloads
  Invoke-WebRequest -UseBasicParsing $Url -OutFile $DestinationPath
}

function Get-InstallPayloadPaths {
  return @(
    'install.sh',
    'install.ps1',
    'skills/ai-cli-config-sync/SKILL.md',
    'skills/ai-cli-config-sync-codex/SKILL.md',
    'scripts/push.sh',
    'scripts/pull.sh',
    'scripts/setup.sh',
    'scripts/sync.sh',
    'scripts/status.sh',
    'scripts/enable-auto-sync.sh',
    'scripts/runtime.ps1',
    'scripts/push.ps1',
    'scripts/pull.ps1',
    'scripts/setup.ps1',
    'scripts/sync.ps1',
    'scripts/status.ps1',
    'scripts/enable-auto-sync.ps1'
  )
}

function Copy-InstallPayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot
  )

  foreach ($relativePath in (Get-InstallPayloadPaths)) {
    $sourcePath = Resolve-PayloadPath -BasePath $SourceRoot -RelativePath $relativePath
    if (-not (Test-Path $sourcePath)) {
      throw "Install payload is incomplete. Missing required file: $sourcePath"
    }

    $destinationPath = Resolve-PayloadPath -BasePath $DestinationRoot -RelativePath $relativePath
    $destinationDir = Split-Path -Parent $destinationPath
    if ($destinationDir) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
  }
}

function Download-InstallPayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,

    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [string]$CurrentScriptPath
  )

  $trimmedBaseUrl = $BaseUrl.TrimEnd('/')
  foreach ($relativePath in (Get-InstallPayloadPaths)) {
    $destinationPath = Resolve-PayloadPath -BasePath $DestinationRoot -RelativePath $relativePath

    if ($relativePath -eq 'install.ps1' -and $CurrentScriptPath -and (Test-Path $CurrentScriptPath)) {
      $destinationDir = Split-Path -Parent $destinationPath
      if ($destinationDir) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
      }
      Copy-Item -Path $CurrentScriptPath -Destination $destinationPath -Force
      continue
    }

    Invoke-DownloadFile -Url ($trimmedBaseUrl + '/' + $relativePath) -DestinationPath $destinationPath
  }
}

function Get-GitBashPath {
  $gitCommand = Get-Command git -ErrorAction SilentlyContinue
  if (-not $gitCommand) {
    throw "git was not found. Please install Git for Windows and ensure git is on PATH."
  }

  $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
  $bashPath = Join-Path $gitRoot 'bin\bash.exe'
  if (-not (Test-Path $bashPath)) {
    throw "Detected git at $($gitCommand.Source), but could not find the matching Git Bash at $bashPath"
  }
  return $bashPath
}

function Invoke-InstallScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallShPath
  )

  $bashPath = Get-GitBashPath
  $bashFriendlyPath = $InstallShPath.Replace('\', '/')
  & $bashPath -lc ('bash "{0}"' -f $bashFriendlyPath)
  $exitCode = $LASTEXITCODE
  if ($null -ne $exitCode -and $exitCode -ne 0) {
    exit $exitCode
  }
}

$installPayloadSourceDir = [Environment]::GetEnvironmentVariable('AI_CLI_SYNC_INSTALL_SOURCE_DIR', 'Process')
$installPayloadBaseUrl = [Environment]::GetEnvironmentVariable('AI_CLI_SYNC_INSTALL_BASE_URL', 'Process')
if ([string]::IsNullOrWhiteSpace($installPayloadBaseUrl)) {
  $installPayloadBaseUrl = 'https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main'
}

$scriptDir = if ($MyInvocation.MyCommand.Path) {
  Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
  $null
}

$installShPath = if ($scriptDir) {
  Join-Path $scriptDir 'install.sh'
} else {
  $null
}

$tempDir = $null
try {
  if (-not $installShPath -or -not (Test-Path $installShPath)) {
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("ai-cli-config-sync-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($installPayloadSourceDir)) {
      Copy-InstallPayload -SourceRoot $installPayloadSourceDir -DestinationRoot $tempDir
    } else {
      Download-InstallPayload -DestinationRoot $tempDir -BaseUrl $installPayloadBaseUrl -CurrentScriptPath $MyInvocation.MyCommand.Path
    }

    $installShPath = Join-Path $tempDir 'install.sh'
  }

  Invoke-InstallScript -InstallShPath $installShPath
}
finally {
  if ($tempDir -and (Test-Path $tempDir)) {
    Remove-Item -Path $tempDir -Recurse -Force
  }
}
