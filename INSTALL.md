# Installation

The recommended installation path is intentionally designed to avoid Windows PowerShell execution-policy problems.

## Quick install

1. Enable qBittorrent Web UI.
2. Enable **Bypass authentication for clients on localhost**.
3. Set qBittorrent **Maximum active downloads = 1**.
4. Turn **Do not count slow torrents in these limits** OFF.
5. Extract the release ZIP.
6. Double-click **install.cmd**.
7. Enter the Web UI URL when asked, e.g. `http://127.0.0.1:8080`.

`install.cmd` uses:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass
```

This is deliberate. It avoids the common Windows error:

```text
The file install.ps1 is not digitally signed
```

without permanently changing the user's PowerShell execution policy.

## What the installer does

- Stops older qBit Smart Queue copies
- Copies the app into `%LOCALAPPDATA%\qBitSmartQueue`
- Creates the user's private `config.json`
- Tests the qBittorrent Web API
- Creates a hidden Startup launcher
- Starts qBit Smart Queue immediately
- Requires no Administrator rights

## Upgrade

Extract a newer release and run `install.cmd` again.

If an existing config is present, the installer uses its current qBittorrent URL as the default prompt value.

## Uninstall

Double-click `uninstall.cmd`.

## Downloading metadata

Magnet links stuck in qBittorrent's `metaDL` / **Downloading metadata** state are also monitored. The default timeout is 180 seconds and can be changed with `MetadataTimeoutSeconds` in the installed `config.json`.
