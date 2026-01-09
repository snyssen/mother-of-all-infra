# Syncthing Stack

## Overview

The **Syncthing** stack provides decentralized, end-to-end encrypted file synchronization between multiple devices. It replaces proprietary sync services like Dropbox or OneDrive by offering complete control, privacy, and the ability to sync to your own server rather than relying on cloud providers.

## Components

### Syncthing

- **Image**: `lscr.io/linuxserver/syncthing:2.0.13`
- **Purpose**: Decentralized file synchronization engine
- **Container Name**: `syncthing`
- **Web UI**: `https://sync.{{ main_domain }}`
- **Storage**: `/mnt/storage/syncthing/`

## Key Features

- **Decentralized**: No central server required, peer-to-peer synchronization
- **End-to-End Encrypted**: All transfers encrypted between devices
- **Selective Sync**: Choose which folders to sync on each device
- **Versioning**: Keep version history of changed files
- **Bandwidth Control**: Limit upload/download speeds
- **Conflict Resolution**: Automatic handling of file conflicts
- **File Ignoring**: Exclude files using ignore patterns
- **Device Discovery**: Automatic discovery of other Syncthing devices
- **Web Interface**: Manage settings and monitor sync status
- **Multi-Platform**: Available for Windows, macOS, Linux, Android, iOS

## Network Configuration

- **web network**: Web UI access via Traefik
- **ldap network**: User authentication (optional)
- **lan network**: LAN discovery for local network sync

## Connection Methods

### Web Interface (via Traefik)

- **Access**: `https://sync.{{ main_domain }}`
- **Port**: 8384 (internally)
- **Network**: `web` via HTTPS

### Direct Sync (P2P)

- **TCP Port**: 22000 (direct connections)
- **UDP Port**: 22000 (UDP discovery/transfer)
- **Port 21027**: Device discovery protocol

### LAN Discovery

- **UDP Port**: 21027 - Local network device discovery
- **Zero-configuration**: Devices automatically discover each other on LAN

## Storage

- **Sync Directory**: `/mnt/storage/syncthing/` - all synchronized files
- **Configuration**: Per-device settings stored locally
- **Database**: File index and metadata for fast sync operations

## Permissions

- Runs as the configured user (PUID/PGID)
- Allows file access with proper ownership
- Supports flexible permission models

## Security Features

- **End-to-End Encryption**: All transfers encrypted with device-specific keys
- **Device Verification**: Manually or automatically verify device identities
- **Global Device ID**: Unique identifier for each Syncthing device
- **TLS Connections**: Encrypted communication between devices
- **Web UI Authentication**: Protect access to web interface
- **Rate Limiting**: Prevent abuse of sync protocol

## Deployment Notes

- Container runs as specified user/group (PUID/PGID)
- Syncthing automatically manages database and versioning
- Multiple folders can be synchronized to different locations
- Devices must be added manually or via discovery mechanism
- Bandwidth limits can be configured per-device or per-folder
- Ignore patterns support standard wildcards and regex

## Device Synchronization Workflow

1. **Add Device**: Exchange device IDs with other Syncthing instances
2. **Create Folder**: Define folder to synchronize
3. **Share Folder**: Select which devices have access
4. **Auto-Discovery**: Find other devices on network or via configured servers
5. **Sync**: Changes propagated automatically to all devices

## User-Facing Features

- **Folder Management**: Create and manage sync folders
- **Device Management**: Add and remove other devices
- **Conflict Resolution**: Choose how to handle file conflicts
- **Versioning**: Configure versioning for deleted/changed files
- **Selective Sync**: Selectively download folders on each device
- **File Ignoring**: Exclude files from sync
- **Bandwidth Limits**: Throttle upload/download speeds
- **Web UI**: Monitor sync progress and status
- **Mobile Apps**: iOS and Android apps for syncing on mobile

## Use Cases

- **Home Directory**: Sync configuration files across computers
- **Documents**: Keep documents synchronized across devices
- **Photos**: Sync photos from phone to server automatically
- **Projects**: Collaborate on files without central server
- **Backups**: Maintain multiple copies of important files

## Performance Considerations

- **Initial Sync**: Large initial synchronization may take time
- **Bandwidth**: Can be limited to prevent network congestion
- **Storage**: Requires sufficient disk space for all synced files
- **Database**: File index requires some disk I/O for metadata

## Related Documentation

Syncthing operates independently but can work alongside the Backbone stack for web UI access and the LAN for local peer discovery.
