Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$marker = 'ai-cli-config-sync-hook-start'
if (Select-String -Path $PROFILE -Pattern $marker -Quiet -ErrorAction SilentlyContinue) {
  Write-Host "Auto-sync hook already exists in $PROFILE"
  exit 0
}

$hook = @'

# >>> ai-cli-config-sync-hook-start >>>
$CliSyncDir = Join-Path $HOME ".cli-sync"
$ConfigFile = Join-Path $CliSyncDir "config.yml"
$PullScript = Join-Path $CliSyncDir "pull.ps1"
$PushScript = Join-Path $CliSyncDir "push.ps1"
$LogFile = Join-Path $CliSyncDir "auto-sync.log"

if ((Test-Path $ConfigFile) -and (Test-Path $PullScript)) {
  New-Item -ItemType Directory -Path $CliSyncDir -Force | Out-Null
  $configText = Get-Content -Path $ConfigFile -Raw -ErrorAction SilentlyContinue
  if ($configText -match '(?im)^\s*auto_pull:\s*true\s*$') {
    $pullCommand = "& '" + $PullScript.Replace("'", "''") + "' *>> '" + $LogFile.Replace("'", "''") + "'"
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-Command', $pullCommand
    ) -WindowStyle Hidden
  }
}

if (-not $Global:AiCliSyncPushOnExitRegistered) {
  $Global:AiCliSyncPushOnExitRegistered = $true
  Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    $CliSyncDir = Join-Path $HOME ".cli-sync"
    $ConfigFile = Join-Path $CliSyncDir "config.yml"
    $PushScript = Join-Path $CliSyncDir "push.ps1"
    $LogFile = Join-Path $CliSyncDir "auto-sync.log"
    if ((Test-Path $ConfigFile) -and (Test-Path $PushScript)) {
      $configText = Get-Content -Path $ConfigFile -Raw -ErrorAction SilentlyContinue
      if ($configText -match '(?im)^\s*auto_push:\s*true\s*$') {
        & $PushScript *>> $LogFile
      }
    }
  } | Out-Null
}
# <<< ai-cli-config-sync-hook-end <<<
'@

Add-Content -Path $PROFILE -Value $hook

Write-Host "Auto-sync hook written to $PROFILE"
Write-Host "Edit ~/.cli-sync/config.yml and set auto_pull and/or auto_push to true to enable it."
