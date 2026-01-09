# Streaming Stack

## Overview

The **Streaming** stack provides a self-hosted media server for managing and streaming movies, TV shows, music, and photos. It offers a user-friendly interface for video streaming with support for transcoding, client discovery, and multi-user access. It replaces services like Plex or Emby.

## Components

### Jellyfin

- **Image**: `ghcr.io/jellyfin/jellyfin:10.11.5`
- **Purpose**: Media server for organizing and streaming video/audio/photos
- **Container Name**: `jellyfin`
- **Access**: `https://streaming.{{ main_domain }}`
- **Storage**: `/mnt/storage/streaming/`

### Additional Services

- **Plex** (optional): Alternative media server implementation
- **Other media services**: Configured as needed

## Key Features

- **Video Streaming**: Stream movies and TV shows with adaptive bitrate
- **Audio Streaming**: Stream music with gapless playback and ReplayGain support
- **Photo Galleries**: Browse and present photos with slideshow
- **Hardware Transcoding**: Intel QuickSync support for efficient transcoding (via `/dev/dri`)
- **Client Discovery**: Automatic discovery on LAN via UDP port 7359
- **Multi-Device Support**: Play on multiple devices simultaneously
- **User Management**: Multiple user profiles with separate libraries
- **Smart Playlists**: Create dynamic playlists based on criteria
- **Library Organization**: Automatic recognition and organization of media

## Dependencies

### Required Stacks

- **Backbone**: Traefik for HTTPS and hostname routing
- **Monitoring** (optional): Service performance monitoring

### Optional Stacks

- **Databases**: Some plugins may require database backend
- **Network Services**: For DLNA and local network discovery

## Network Configuration

- **web network**: Public access via Traefik
- **monitoring network**: Performance metrics collection
- **ldap network**: Authentication integration (optional)

## Storage

- **Media Directory**: `/mnt/storage/streaming/` - stores all media files
- **Cache Directory**: `/cache/` - thumbnails and transcoding cache
- **Configuration**: `/config/` - application configuration
- **Data Directory**: `/data/` - application data
- **Logs**: `/logs/` - application logs

## Hardware Acceleration

- **Intel QuickSync**: Enabled for H.264 and H.265 transcoding
- **Device Mapping**: `/dev/dri` mounted for GPU access
- **Render Group**: GID 109 (render group) for GPU permission

## Deployment Notes

- Runs as UID 33 (www-data) with group flexibility for access control
- Supports both absolute and relative paths for media organization
- Published server URL configured for proper remote access URLs
- Hardware transcoding available when GPU device is present
- Playlist duplicates are disabled for cleaner library management
- Data stored persistently across restarts

## User-Facing Features

- **Web Interface**: Browse libraries, manage playlists, adjust settings
- **Mobile Apps**: iOS and Android apps for mobile streaming
- **Desktop Clients**: Windows, macOS, Linux dedicated clients
- **PlayTo Support**: Control playback via DLNA devices
- **Sync Playback**: Keep playback synchronized across devices
- **Recommendations**: Get suggestions based on watch history
- **Artwork Management**: Auto-fetch and manage media artwork
- **Parental Controls**: Create restricted accounts for children
- **Direct Play**: Stream without transcoding when possible
- **Adaptive Bitrate**: Stream at quality appropriate for connection speed

## Media Organization

Jellyfin automatically recognizes common media folder structures:

- **Movies**: `/movies/` folder containing movie files
- **TV Shows**: `/tv/` folder with series/season/episode structure
- **Music**: `/music/` folder organized by artist/album/tracks
- **Photos**: `/photos/` folder with image collections
- **Live TV**: Can be configured for DVR and live TV

## Related Documentation

Streaming integrates with the Monitoring stack for performance metrics and optionally with the Databases stack for plugin support.
