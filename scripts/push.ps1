Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'runtime.ps1')

Invoke-AiCliSyncBashScript -ScriptName 'push.sh'
