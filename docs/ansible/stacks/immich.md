# Immich Stack

## Overview

The **Immich** stack provides a modern, self-hosted photo and video management platform with automatic organization, intelligent search, and sharing capabilities. It replaces Google Photos with a privacy-first alternative that keeps all media on your own server.

## Components

### Immich Server

- **Image**: `ghcr.io/immich-app/immich-server:v2.4.1`
- **Purpose**: Photo/video processing, API, and web interface
- **Container Name**: `immich_server`
- **Access**: `https://photos.{{ main_domain }}`
- **Storage**: `/mnt/storage/photos/`

### Immich Microservices

- **Purpose**: Background tasks like thumbnail generation, ML recognition
- **Deployed alongside Immich Server**

### Immich Database (PostgreSQL)

- **Container Name**: `database`
- **Database Name**: `immich`
- **Network**: `internal` (shared database from Databases stack)

### Immich Redis

- **Container Name**: `redis`
- **Purpose**: Caching and job queue
- **Network**: `internal`

## Key Features

- **Automatic Imports**: Watch folders for new photos/videos and import automatically
- **Smart Organization**: Automatic classification and organization by date, location, camera
- **Search**: Full-text search with support for dates, locations, and camera metadata
- **Sharing**: Create albums and share with other users
- **Mobile Apps**: iOS and Android apps for backup and viewing
- **Machine Learning**: On-device or cloud-based image recognition and object detection
- **Backup Integration**: Automatic daily backups to `/mnt/storage/backups/immich/`

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL database for photo metadata and user accounts
- **Backbone**: Traefik for HTTPS termination and routing
- **Monitoring** (optional): Service health monitoring

## Network Configuration

- **web network**: Exposed via Traefik for public access
- **internal network**: Internal communication with other services
- **db network**: Database connectivity

## Storage

- **Photos Directory**: `/mnt/storage/photos/` - stores all uploaded photos and videos
- **Backups**: `/mnt/storage/backups/immich/` - automated backups of the library

## Monitoring

- HTTP monitor via Uptime Kuma at `https://photos.{{ main_domain }}`
- Health checks ensure service availability

## Deployment Notes

- Immich Server contains both API and web UI in one container
- Requires PostgreSQL database with user `immich`
- Redis instance provides caching and job queue functionality
- Storage volume must have sufficient space for photo library
- Automatic backups are configured and run regularly
- Container runs as non-root user for security

## User-Facing Features

- **Web Gallery**: Browse and search photos and videos
- **Album Management**: Organize media into albums
- **Sharing**: Share albums with other users or generate public links
- **Timeline View**: Chronological view of all media
- **Map View**: View photos on an interactive map using EXIF data
- **Face Recognition**: Identify and group people in photos
- **Mobile Backup**: Automatic backup of photos from mobile devices
- **Collaborative Albums**: Share and contribute to shared albums

## Related Documentation

Immich integrates with the Monitoring stack for health checks and uses the Databases stack for metadata storage.
