param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:AppName = "qBit Smart Queue"
$script:Version = "0.3.1"
$script:BaseDir = $PSScriptRoot
$script:LogDir = Join-Path $script:BaseDir "logs"
$script:StatusPath = Join-Path $script:BaseDir "status.json"
$script:RetryStatePath = Join-Path $script:BaseDir "retry-state.json"

New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null

# Prevent multiple copies from controlling the same qBittorrent instance.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "qBitSmartQueue.SingleInstance", [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "qBit Smart Queue is already running."
    exit 2
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","ACTION")]
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $logPath = Join-Path $script:LogDir ("smart-queue-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
    Add-Content -Path $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Load-Config {
    if (-not (Test-Path $ConfigPath)) {
        throw "Config not found: $ConfigPath. Run install.cmd or copy config.example.json to config.json."
    }

    $cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

    $required = @(
        "QbitUrl",
        "MinSpeedKiB",
        "SlowSeconds",
        "MetadataTimeoutSeconds",
        "CheckIntervalSeconds",
        "CooldownMinutes",
        "RevisitGraceSeconds",
        "StartupGraceSeconds",
        "StatusLogEverySeconds",
        "LogRetentionDays",
        "DryRun"
    )

    foreach ($name in $required) {
        if ($null -eq $cfg.$name) {
            throw "Missing config value: $name"
        }
    }

    return $cfg
}

function Save-RetryState {
    param([hashtable]$RetryAfter)

    $out = @{}
    foreach ($key in $RetryAfter.Keys) {
        $out[$key] = $RetryAfter[$key].ToString("o")
    }

    $out | ConvertTo-Json | Set-Content -Path $script:RetryStatePath -Encoding UTF8
}

function Load-RetryState {
    $table = @{}

    if (-not (Test-Path $script:RetryStatePath)) {
        return $table
    }

    try {
        $obj = Get-Content -Raw -Path $script:RetryStatePath | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) {
            $dt = [datetime]::MinValue
            if ([datetime]::TryParse([string]$p.Value, [ref]$dt) -and $dt -gt (Get-Date)) {
                $table[$p.Name] = $dt
            }
        }
    }
    catch {
        Write-Log "Could not load retry state. Starting fresh: $($_.Exception.Message)" "WARN"
    }

    return $table
}

function Write-Status {
    param(
        [string]$Connection = "unknown",
        $Current = $null,
        [double]$SpeedKiB = 0,
        [string]$Note = ""
    )

    $status = [ordered]@{
        App = $script:AppName
        Version = $script:Version
        ProcessId = $PID
        LastHeartbeat = (Get-Date).ToString("o")
        Connection = $Connection
        CurrentTorrent = if ($null -ne $Current) { [string]$Current.name } else { $null }
        State = if ($null -ne $Current) { [string]$Current.state } else { $null }
        SpeedKiB = [math]::Round($SpeedKiB, 1)
        Note = $Note
    }

    $status | ConvertTo-Json | Set-Content -Path $script:StatusPath -Encoding UTF8
}

function Get-Headers {
    param([string]$QbitUrl)

    $headers = @{ Referer = ($QbitUrl.TrimEnd("/") + "/") }

    # Optional qBittorrent 5.2+ API key.
    # Never store the key in config.json; use the QBIT_API_KEY environment variable.
    if (-not [string]::IsNullOrWhiteSpace($env:QBIT_API_KEY)) {
        $headers["Authorization"] = "Bearer $($env:QBIT_API_KEY)"
    }

    return $headers
}

function Invoke-QbitGet {
    param(
        [string]$QbitUrl,
        [hashtable]$Headers,
        [string]$Endpoint
    )

    Invoke-RestMethod `
        -Uri ($QbitUrl.TrimEnd("/") + "/api/v2/" + $Endpoint) `
        -Headers $Headers `
        -Method Get `
        -TimeoutSec 10
}

function Invoke-QbitPost {
    param(
        [string]$QbitUrl,
        [hashtable]$Headers,
        [string]$Endpoint,
        [hashtable]$Body
    )

    Invoke-RestMethod `
        -Uri ($QbitUrl.TrimEnd("/") + "/api/v2/" + $Endpoint) `
        -Headers $Headers `
        -Method Post `
        -Body $Body `
        -ContentType "application/x-www-form-urlencoded" `
        -TimeoutSec 10 | Out-Null
}

function Get-Torrents {
    param([string]$QbitUrl, [hashtable]$Headers)
    @(Invoke-QbitGet -QbitUrl $QbitUrl -Headers $Headers -Endpoint "torrents/info")
}

function Is-ForceStarted {
    param($Torrent)
    return ($Torrent.PSObject.Properties.Name -contains "force_start" -and [bool]$Torrent.force_start)
}

function Get-CurrentTorrent {
    param($Torrents)

    $Torrents |
        Where-Object {
            $_.progress -lt 1 -and
            $_.state -in @("downloading", "stalledDL", "metaDL") -and
            -not (Is-ForceStarted $_)
        } |
        Sort-Object priority |
        Select-Object -First 1
}

function Get-NextQueuedTorrent {
    param($Torrents, [string]$ExcludeHash)

    $Torrents |
        Where-Object {
            $_.progress -lt 1 -and
            $_.state -eq "queuedDL" -and
            $_.hash -ne $ExcludeHash -and
            -not (Is-ForceStarted $_)
        } |
        Sort-Object priority |
        Select-Object -First 1
}

function Rotate-Torrent {
    param($Current, $Next, $Config, [hashtable]$Headers)

    $currentName = [string]$Current.name
    $nextName = [string]$Next.name

    if ($Config.DryRun) {
        Write-Log "DRY RUN: would move '$currentName' to the bottom and let '$nextName' run next." "ACTION"
        return
    }

    Invoke-QbitPost -QbitUrl $Config.QbitUrl -Headers $Headers -Endpoint "torrents/stop" -Body @{ hashes = $Current.hash }
    Start-Sleep -Milliseconds 750

    Invoke-QbitPost -QbitUrl $Config.QbitUrl -Headers $Headers -Endpoint "torrents/bottomPrio" -Body @{ hashes = $Current.hash }
    Start-Sleep -Milliseconds 500

    Invoke-QbitPost -QbitUrl $Config.QbitUrl -Headers $Headers -Endpoint "torrents/start" -Body @{ hashes = $Next.hash }
    Start-Sleep -Milliseconds 750

    # Re-enable the old torrent. With max active downloads = 1 it stays queued at the bottom.
    Invoke-QbitPost -QbitUrl $Config.QbitUrl -Headers $Headers -Endpoint "torrents/start" -Body @{ hashes = $Current.hash }

    Write-Log "Rotated '$currentName' -> bottom. Next: '$nextName'." "ACTION"
}

try {
    $config = Load-Config
    $headers = Get-Headers -QbitUrl $config.QbitUrl

    Get-ChildItem -Path $script:LogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-[int]$config.LogRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $slowSince = @{}
    $watchMode = @{}
    $retryAfter = Load-RetryState
    $lastStatusLog = [datetime]::MinValue
    $connectedOnce = $false

    Write-Log "$($script:AppName) v$($script:Version) starting."
    Write-Log ("Config: URL={0}, threshold={1} KiB/s, slow={2}s, cooldown={3}m, dryRun={4}" -f `
        $config.QbitUrl, $config.MinSpeedKiB, $config.SlowSeconds, $config.CooldownMinutes, $config.DryRun)

    while ($true) {
        try {
            $torrents = Get-Torrents -QbitUrl $config.QbitUrl -Headers $headers

            if (-not $connectedOnce) {
                $connectedOnce = $true
                Write-Status -Connection "connected" -Note "Startup grace"
                Write-Log "Connected to qBittorrent. Waiting $($config.StartupGraceSeconds)s before monitoring."
                Start-Sleep -Seconds ([int]$config.StartupGraceSeconds)
                continue
            }

            $current = Get-CurrentTorrent -Torrents $torrents

            if ($null -eq $current) {
                $slowSince.Clear()
                $watchMode.Clear()
                Write-Status -Connection "connected" -Note "No active monitored download"

                if (((Get-Date) - $lastStatusLog).TotalSeconds -ge [int]$config.StatusLogEverySeconds) {
                    Write-Log "No active downloading/stalled torrent."
                    $lastStatusLog = Get-Date
                }

                Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
                continue
            }

            $speedKiB = [double]$current.dlspeed / 1KB
            $thresholdBytes = [double]$config.MinSpeedKiB * 1KB
            $now = Get-Date
            $next = Get-NextQueuedTorrent -Torrents $torrents -ExcludeHash $current.hash
            $isMetadata = ([string]$current.state -eq "metaDL")
            $currentMode = if ($isMetadata) { "metadata" } else { "speed" }

            Write-Status -Connection "connected" -Current $current -SpeedKiB $speedKiB `
                -Note $(if ($isMetadata) { "Fetching metadata" } else { "" })

            if (($now - $lastStatusLog).TotalSeconds -ge [int]$config.StatusLogEverySeconds) {
                if ($isMetadata) {
                    Write-Log ("'{0}' | metaDL | fetching metadata" -f $current.name)
                }
                else {
                    Write-Log ("'{0}' | {1} | {2:N0} KiB/s" -f $current.name, $current.state, $speedKiB)
                }
                $lastStatusLog = $now
            }

            # Normal downloads recover when speed rises above the threshold.
            # Metadata fetching is handled by its own timeout instead of download speed.
            if (-not $isMetadata -and [double]$current.dlspeed -ge $thresholdBytes) {
                if ($slowSince.ContainsKey($current.hash)) {
                    $slowSince.Remove($current.hash)
                }
                if ($watchMode.ContainsKey($current.hash)) {
                    $watchMode.Remove($current.hash)
                }

                if ($retryAfter.ContainsKey($current.hash)) {
                    $retryAfter.Remove($current.hash)
                    Save-RetryState -RetryAfter $retryAfter
                    Write-Log "'$($current.name)' recovered above threshold; cooldown cleared."
                }

                Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
                continue
            }

            # Do not rotate if nothing else is waiting.
            if ($null -eq $next) {
                if ($slowSince.ContainsKey($current.hash)) {
                    $slowSince.Remove($current.hash)
                }
                if ($watchMode.ContainsKey($current.hash)) {
                    $watchMode.Remove($current.hash)
                }

                Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
                continue
            }

            $requiredSlowSeconds = if ($isMetadata) {
                [int]$config.MetadataTimeoutSeconds
            } else {
                [int]$config.SlowSeconds
            }

            # Recently skipped torrents only get a short grace window when they return
            # and are still slow / still stuck fetching metadata.
            if ($retryAfter.ContainsKey($current.hash)) {
                if ($retryAfter[$current.hash] -gt $now) {
                    $requiredSlowSeconds = [int]$config.RevisitGraceSeconds
                }
                else {
                    $retryAfter.Remove($current.hash)
                    Save-RetryState -RetryAfter $retryAfter
                }
            }

            # Reset the timer if the torrent changes mode, e.g. metaDL -> downloading.
            if (-not $slowSince.ContainsKey($current.hash) -or
                -not $watchMode.ContainsKey($current.hash) -or
                $watchMode[$current.hash] -ne $currentMode) {

                $slowSince[$current.hash] = $now
                $watchMode[$current.hash] = $currentMode

                if ($isMetadata) {
                    Write-Log ("'{0}' is fetching metadata. Timer started; metadata limit={1}s." -f `
                        $current.name, $requiredSlowSeconds) "WARN"
                }
                else {
                    Write-Log ("'{0}' is below threshold ({1:N0} KiB/s). Timer started; limit={2}s." -f `
                        $current.name, $speedKiB, $requiredSlowSeconds) "WARN"
                }

                Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
                continue
            }

            $slowFor = ($now - $slowSince[$current.hash]).TotalSeconds
            if ($slowFor -lt $requiredSlowSeconds) {
                Start-Sleep -Seconds ([int]$config.CheckIntervalSeconds)
                continue
            }

            if ($isMetadata) {
                Write-Log ("'{0}' stayed in metaDL for {1:N0}s. Rotating." -f `
                    $current.name, $slowFor) "ACTION"
            }
            else {
                Write-Log ("'{0}' stayed below {1} KiB/s for {2:N0}s. Rotating." -f `
                    $current.name, $config.MinSpeedKiB, $slowFor) "ACTION"
            }

            Rotate-Torrent -Current $current -Next $next -Config $config -Headers $headers

            $retryAfter[$current.hash] = (Get-Date).AddMinutes([int]$config.CooldownMinutes)
            Save-RetryState -RetryAfter $retryAfter
            $slowSince.Remove($current.hash)
            if ($watchMode.ContainsKey($current.hash)) {
                $watchMode.Remove($current.hash)
            }

            Start-Sleep -Seconds ([math]::Max(5, [int]$config.CheckIntervalSeconds))
        }
        catch {
            $msg = $_.Exception.Message

            if ($msg -match "403|Forbidden") {
                Write-Log "qBittorrent returned 403 Forbidden. Enable 'Bypass authentication for clients on localhost' or set QBIT_API_KEY, and verify QbitUrl/port." "ERROR"
            }
            elseif ($msg -match "409") {
                Write-Log "qBittorrent returned 409. Torrent queueing may be disabled; bottomPrio requires queueing." "ERROR"
            }
            else {
                Write-Log "qBittorrent/API error: $msg" "ERROR"
            }

            Write-Status -Connection "error" -Note $msg
            Start-Sleep -Seconds 15
        }
    }
}
finally {
    try { Write-Log "$($script:AppName) stopping." } catch {}
    try {
        if ($null -ne $mutex) {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }
    } catch {}
}
