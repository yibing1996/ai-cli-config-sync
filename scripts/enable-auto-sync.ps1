Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetProfile = $PROFILE
if ([string]::IsNullOrWhiteSpace($targetProfile)) {
  $profileHome = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $env:USERPROFILE
  } elseif (-not [string]::IsNullOrWhiteSpace($HOME)) {
    $HOME
  } else {
    throw 'Unable to determine the current user profile directory for PowerShell auto-sync.'
  }

  $targetProfile = Join-Path $profileHome 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
}

$profileDir = Split-Path -Parent $targetProfile
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $targetProfile)) {
  New-Item -ItemType File -Path $targetProfile -Force | Out-Null
}

$marker = 'ai-cli-config-sync-hook-start'
$startMarker = '# >>> ai-cli-config-sync-hook-start >>>'
$endMarker = '# <<< ai-cli-config-sync-hook-end <<<'
$existingProfileText = Get-Content -Path $targetProfile -Raw -ErrorAction SilentlyContinue
if ($null -eq $existingProfileText) {
  $existingProfileText = ''
}

$existingProfileText = [regex]::Replace(
  $existingProfileText,
  '(?ms)^\s*# >>> ai-cli-config-sync-hook-start >>>.*?# <<< ai-cli-config-sync-hook-end <<<\r?\n?',
  ''
).TrimEnd()

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
    $pullCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" >> "{1}" 2>>&1' -f $PullScript.Replace('"', '""'), $LogFile.Replace('"', '""')
    Start-Process -FilePath "cmd.exe" -ArgumentList @(
      '/d',
      '/c',
      $pullCommand
    ) -WindowStyle Hidden | Out-Null
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
        $pushCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" >> "{1}" 2>>&1' -f $PushScript.Replace('"', '""'), $LogFile.Replace('"', '""')
        Start-Process -FilePath "cmd.exe" -ArgumentList @(
          '/d',
          '/c',
          $pushCommand
        ) -WindowStyle Hidden | Out-Null
      }
    }
  } | Out-Null
}
# <<< ai-cli-config-sync-hook-end <<<
'@

$newProfileText = if ([string]::IsNullOrWhiteSpace($existingProfileText)) {
  $hook.TrimStart("`r", "`n")
} else {
  $existingProfileText + "`r`n" + $hook.TrimStart("`r", "`n")
}
[System.IO.File]::WriteAllText($targetProfile, $newProfileText, [System.Text.UTF8Encoding]::new($true))

Write-Host "Auto-sync hook written/updated in $targetProfile"
Write-Host "Edit ~/.cli-sync/config.yml and set auto_pull and/or auto_push to true to enable it."
