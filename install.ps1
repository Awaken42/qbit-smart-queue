param(
    [switch]$StartNow,
    [switch]$KeepExistingConfig,
    [string]$QbitUrl
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$sourceDir = $PSScriptRoot
$installDir = Join-Path $env:LOCALAPPDATA "qBitSmartQueue"
$startupDir = [Environment]::GetFolderPath("Startup")
$launcherPath = Join-Path $startupDir "qbit-smart-queue.vbs"
$installedScript = Join-Path $installDir "qbit-smart-queue.ps1"
$installedConfig = Join-Path $installDir "config.json"

function Stop-OldInstances {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*qbit-smart-queue.ps1*" -and $_.ProcessId -ne $PID } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Ask-Value {
    param([string]$Prompt, [string]$Default)
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Test-QbitUrl {
    param([string]$Url)

    try {
        $version = Invoke-RestMethod `
            -Uri ($Url.TrimEnd("/") + "/api/v2/app/version") `
            -Method Get `
            -TimeoutSec 5
        return @{ Result = "OK"; Message = [string]$version }
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match "403|Forbidden") {
            return @{ Result = "AUTH"; Message = $msg }
        }
        return @{ Result = "FAIL"; Message = $msg }
    }
}

Write-Host ""
Write-Host "========================================="
Write-Host " qBit Smart Queue installer v0.3.1"
Write-Host "========================================="
Write-Host ""

Stop-OldInstances

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $installDir "logs") | Out-Null

Copy-Item (Join-Path $sourceDir "qbit-smart-queue.ps1") $installedScript -Force

$existingConfig = Test-Path $installedConfig
$template = Get-Content -Raw (Join-Path $sourceDir "config.example.json") | ConvertFrom-Json

if ($existingConfig) {
    # Preserve all existing user settings and add any new defaults introduced by upgrades.
    $old = Get-Content -Raw $installedConfig | ConvertFrom-Json
    $merged = [ordered]@{}

    foreach ($prop in $template.PSObject.Properties) {
        if ($old.PSObject.Properties.Name -contains $prop.Name) {
            $merged[$prop.Name] = $old.($prop.Name)
        }
        else {
            $merged[$prop.Name] = $prop.Value
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($QbitUrl)) {
        $merged["QbitUrl"] = $QbitUrl
    }

    $merged | ConvertTo-Json | Set-Content -Path $installedConfig -Encoding UTF8
    Write-Host "Existing config preserved and upgraded with any new defaults."
}
else {
    if ([string]::IsNullOrWhiteSpace($QbitUrl)) {
        $QbitUrl = Ask-Value "qBittorrent Web UI URL" "http://127.0.0.1:8080"
    }

    $template.QbitUrl = $QbitUrl
    $template | ConvertTo-Json | Set-Content -Path $installedConfig -Encoding UTF8
}

$config = Get-Content -Raw $installedConfig | ConvertFrom-Json
Write-Host ""
Write-Host "Testing qBittorrent at $($config.QbitUrl) ..."

$test = Test-QbitUrl -Url ([string]$config.QbitUrl)

if ($test.Result -eq "OK") {
    Write-Host "Connected successfully. qBittorrent version: $($test.Message)"
}
elseif ($test.Result -eq "AUTH") {
    Write-Host ""
    Write-Host "qBittorrent answered, but authentication blocked the local API (403)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "In qBittorrent:"
    Write-Host "  Tools -> Options -> Web UI"
    Write-Host "  1. Enable Web User Interface"
    Write-Host "  2. Check 'Bypass authentication for clients on localhost'"
    Write-Host "  3. Apply / OK"
    Write-Host ""
    Write-Host "The install will continue. The service retries automatically."
}
else {
    Write-Host ""
    Write-Host "Could not reach qBittorrent right now:" -ForegroundColor Yellow
    Write-Host "  $($test.Message)"
    Write-Host ""
    Write-Host "Make sure qBittorrent is running and the Web UI port in config.json is correct."
    Write-Host "The install will continue; the service retries automatically."
}

$vbs = @"
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$installedScript""", 0, False
"@

Set-Content -Path $launcherPath -Value $vbs -Encoding ASCII

Write-Host ""
Write-Host "Installed to:"
Write-Host "  $installDir"
Write-Host ""
Write-Host "Windows startup launcher:"
Write-Host "  $launcherPath"
Write-Host ""

if ($StartNow) {
    Start-Process "wscript.exe" -ArgumentList "`"$launcherPath`""
    Start-Sleep -Seconds 2
    Write-Host "qBit Smart Queue started in the background."
}

Write-Host ""
Write-Host "Recommended qBittorrent settings:"
Write-Host "  Maximum active downloads: 1"
Write-Host "  Do not count slow torrents in these limits: OFF"
Write-Host "  Avoid Force Start for torrents you want managed"
Write-Host ""
Write-Host "Done."
