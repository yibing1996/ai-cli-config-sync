param(
  [Parameter(Mandatory = $true)]
  [string]$RemoteUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'runtime.ps1')

$env:AI_CLI_SYNC_REMOTE_URL = $RemoteUrl
try {
  Invoke-AiCliSyncBashScript -ScriptName 'setup.sh'
}
finally {
  Remove-Item Env:AI_CLI_SYNC_REMOTE_URL -ErrorAction SilentlyContinue
}
