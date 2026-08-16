# Changelog

## 0.3.0

- Added `install.cmd` as the recommended Windows installer
- Installer automatically uses `-ExecutionPolicy Bypass`, avoiding unsigned-script errors
- Added interactive qBittorrent Web UI URL setup
- Added API connection test during installation
- Added clear 403/local-auth instructions
- Removed user-specific `config.json` from the release/repository
- Added `status.cmd` and `uninstall.cmd`
- Improved upgrade behavior and old-process cleanup
- Preserves existing installed Web UI URL as the next installer default
- Hardened Force Start detection
- Expanded README and dedicated INSTALL.md

## 0.2.0

- Added single-instance protection
- Added cooldown and short retry grace
- Added persistent retry state
- Added daily file logging and retention
- Added status heartbeat
- Added dry-run mode
- Added optional API-key support through `QBIT_API_KEY`
- Added no-admin hidden startup installer
- Added uninstaller and status helper
- Ignores Force Start torrents
- Only rotates when another queued download exists
