Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AiCliSyncWindowsHome {
  if ($env:USERPROFILE -and $env:USERPROFILE.Trim()) {
    return $env:USERPROFILE
  }

  $home = [Environment]::GetFolderPath('UserProfile')
  if (-not $home) {
    throw "Unable to determine the Windows user profile. Please check USERPROFILE."
  }
  return $home
}

function Get-AiCliSyncScriptsDir {
  return Join-Path (Get-AiCliSyncWindowsHome) '.cli-sync'
}

function Get-AiCliSyncGitBashPath {
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

function Invoke-AiCliSyncBashScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName
  )

  $scriptsDir = Get-AiCliSyncScriptsDir
  $windowsScriptPath = Join-Path $scriptsDir $ScriptName
  if (-not (Test-Path $windowsScriptPath)) {
    throw "Missing $windowsScriptPath. Re-run $scriptsDir\install.ps1, or run ~/.cli-sync/install.sh from Git Bash."
  }

  $bashPath = Get-AiCliSyncGitBashPath
  $command = 'bash "$HOME/.cli-sync/{0}"' -f $ScriptName
  $originalLocation = Get-Location
  $originalInputEncoding = [Console]::InputEncoding
  $originalOutputEncoding = [Console]::OutputEncoding
  $originalPipelineEncoding = $global:OutputEncoding
  $chcpPath = Join-Path $env:SystemRoot 'System32\chcp.com'
  $originalCodePage = $null
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  Set-Location (Get-AiCliSyncWindowsHome)
  try {
    if (Test-Path $chcpPath) {
      $codePageOutput = & $chcpPath
      if ($LASTEXITCODE -eq 0 -and $codePageOutput -match '(\d+)\s*$') {
        $originalCodePage = $Matches[1]
      }
      & $chcpPath 65001 | Out-Null
    }

    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $global:OutputEncoding = $utf8NoBom

    & $bashPath -lc $command
    $exitCode = $LASTEXITCODE
    if ($null -ne $exitCode -and $exitCode -ne 0) {
      exit $exitCode
    }
  }
  finally {
    if ($originalCodePage -and (Test-Path $chcpPath)) {
      & $chcpPath $originalCodePage | Out-Null
    }
    [Console]::InputEncoding = $originalInputEncoding
    [Console]::OutputEncoding = $originalOutputEncoding
    $global:OutputEncoding = $originalPipelineEncoding
    Set-Location $originalLocation
  }
}
