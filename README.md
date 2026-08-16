# qBit Smart Queue

A lightweight Windows helper for qBittorrent that keeps a one-at-a-time download queue moving.

When the active torrent stays below a configurable speed for long enough, qBit Smart Queue moves it to the bottom and lets the next queued torrent try. It never deletes the torrent or its data.

## Why

qBittorrent's built-in **Do not count slow torrents in these limits** can cause several slow torrents to run at the same time. qBit Smart Queue instead keeps **one active download** and rotates genuinely slow/stalled torrents out of the way.

## Features

- Below-speed timeout, default **500 KiB/s for 3 minutes**
- Detects magnets stuck on **Downloading metadata (`metaDL`)** and rotates them after a separate timeout
- Handles `downloading`, `stalledDL` and `metaDL`
- Sends slow torrent to the bottom of the queue
- 30-minute cooldown / short retry grace for repeatedly bad torrents
- Single-instance protection
- Hidden Windows startup
- No administrator rights required
- Daily logs and `status.json`
- Dry-run mode
- Ignores Force Start torrents
- Optional qBittorrent 5.2+ API-key authentication
- No passwords/API keys stored in the repo

# Installation — easiest method

## 1. qBittorrent settings

Open:

**Tools → Options → BitTorrent**

Set:

- **Maximum active downloads:** `1`
- **Do not count slow torrents in these limits:** OFF

Do not use **Force Start** on torrents you want qBit Smart Queue to manage.

Then open:

**Tools → Options → Web UI**

- Enable **Web User Interface**
- Note the Web UI port (commonly `8080`)
- For a local-only setup, enable **Bypass authentication for clients on localhost**
- Click **Apply**

You do **not** need to expose the Web UI to the internet.

## 2. Download and extract the release ZIP

Extract the ZIP to any folder.

## 3. Run `install.cmd`

Double-click:

```text
install.cmd
```

That's the recommended install method.

`install.cmd` deliberately launches PowerShell with `-ExecutionPolicy Bypass`, so Windows systems that require signed `.ps1` files do not hit the common **"script is not digitally signed"** error.

The installer asks for the qBittorrent Web UI URL:

```text
http://127.0.0.1:8080
```

If your qBittorrent uses another port, for example `8081`, enter:

```text
http://127.0.0.1:8081
```

The installer tests the API and explains what to change if it receives `403 Forbidden`.

After installation, qBit Smart Queue:

- lives in `%LOCALAPPDATA%\qBitSmartQueue`
- starts hidden
- starts automatically when you sign in to Windows
- requires no Administrator privileges

# Manual installation

If you prefer a terminal, use this instead of running `install.ps1` directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" -StartNow
```

Do **not** use plain:

```powershell
.\install.ps1
```

on machines with an `AllSigned` execution policy, because Windows will reject the unsigned script.

# Defaults

```json
{
  "QbitUrl": "http://127.0.0.1:8080",
  "MinSpeedKiB": 500,
  "SlowSeconds": 180,
  "MetadataTimeoutSeconds": 180,
  "CheckIntervalSeconds": 10,
  "CooldownMinutes": 30,
  "RevisitGraceSeconds": 30,
  "StartupGraceSeconds": 45,
  "StatusLogEverySeconds": 60,
  "LogRetentionDays": 14,
  "DryRun": false
}
```

The user's real configuration is created during installation and is **not included in Git**.

# How the queue logic works

Example:

1. Torrent A downloads at 30 MiB/s → keep it.
2. Torrent A briefly drops to 200 KiB/s → wait.
3. Torrent A remains below 500 KiB/s for 3 minutes.
4. Stop Torrent A.
5. Move Torrent A to the bottom.
6. Start Torrent B.
7. Re-enable Torrent A so it remains queued for a later retry.

A recently skipped torrent that comes back during its cooldown gets only a short retry grace window. If it recovers above the configured threshold, the cooldown is cleared.

For magnet links, `metaDL` is treated separately: if qBittorrent remains on **Downloading metadata** for `MetadataTimeoutSeconds` (default 180 seconds), that torrent is rotated to the bottom and the next queued download gets a chance.

# Status

Double-click:

```text
status.cmd
```

Or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\status.ps1"
```

Installed logs are stored in:

```text
%LOCALAPPDATA%\qBitSmartQueue\logs
```

# Uninstall

Double-click:

```text
uninstall.cmd
```

No administrator rights are required.

# Configuration

After installation:

```text
%LOCALAPPDATA%\qBitSmartQueue\config.json
```

Important options:

- `MinSpeedKiB` — minimum acceptable speed
- `SlowSeconds` — time below threshold before rotating
- `MetadataTimeoutSeconds` — maximum time a magnet may remain in Downloading metadata before rotating
- `CooldownMinutes` — how long a recently skipped torrent is remembered
- `RevisitGraceSeconds` — short grace period if it returns during cooldown
- `DryRun` — log actions without changing the queue

# API-key authentication

For qBittorrent 5.2+, you can use an API key instead of localhost auth bypass.

Set it as a Windows user environment variable:

```powershell
[Environment]::SetEnvironmentVariable("QBIT_API_KEY", "qbt_your_key_here", "User")
```

Then sign out/in or restart the background process.

Do not commit API keys to `config.json`.

# Troubleshooting

### `403 Forbidden`

Check:

**Tools → Options → Web UI → Bypass authentication for clients on localhost**

Also verify that the port in `config.json` matches the Web UI port.

### `The file ... is not digitally signed`

Use `install.cmd`.

If installing manually, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" -StartNow
```

### More than one torrent downloads at once

Check:

- Maximum active downloads = `1`
- Do not count slow torrents in these limits = OFF
- No managed torrents are using Force Start

### Torrent is never moved

There must be another incomplete torrent in `queuedDL`. The tool will not stop a slow torrent if there is nothing useful to rotate to.

# Project files

```text
qbit-smart-queue.ps1
install.ps1
install.cmd
status.ps1
status.cmd
uninstall.ps1
uninstall.cmd
config.example.json
README.md
CHANGELOG.md
LICENSE
.gitignore
```

`config.json`, logs, status and retry state are intentionally ignored by Git.

# License

MIT
