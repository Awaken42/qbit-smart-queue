$installDir = Join-Path $env:LOCALAPPDATA "qBitSmartQueue"
$statusPath = Join-Path $installDir "status.json"

$processes = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*qbit-smart-queue.ps1*" }

if ($processes) {
    Write-Host "Process: RUNNING"
    $processes | Select-Object ProcessId, CommandLine | Format-Table -AutoSize
}
else {
    Write-Host "Process: NOT RUNNING"
}

if (Test-Path $statusPath) {
    Write-Host ""
    Write-Host "Last status:"
    Get-Content -Raw $statusPath | ConvertFrom-Json | Format-List
}
else {
    Write-Host ""
    Write-Host "No status.json found yet."
}
