Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    $installShPath = Join-Path $tempDir 'install.sh'
    Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh' -OutFile $installShPath
  }

  Invoke-InstallScript -InstallShPath $installShPath
}
finally {
  if ($tempDir -and (Test-Path $tempDir)) {
    Remove-Item -Path $tempDir -Recurse -Force
  }
}
