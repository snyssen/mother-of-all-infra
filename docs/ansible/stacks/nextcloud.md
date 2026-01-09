# Nextcloud Stack

## Overview

The **Nextcloud** stack provides a comprehensive self-hosted file synchronization, collaboration, and productivity platform. It replaces proprietary cloud services like Google Drive, OneDrive, and Office 365 with a privacy-focused alternative that offers file storage, calendar management, contacts, and collaborative document editing.

## Components

### Nextcloud

- **Image**: `nextcloud:32.0.3`
- **Purpose**: Main file storage and collaboration server
- **Container Name**: `nextcloud`
- **Access**: `https://cloud.{{ main_domain }}`
- **Storage**: `/mnt/storage/nextcloud/`

### Nextcloud Redis

- **Image**: `redis:8.4.0`
- **Purpose**: Caching layer for performance optimization
- **Container Name**: `nextcloud_redis`
- **Memory Limit**: 32MB

## Key Features

- **File Synchronization**: Desktop and mobile clients sync files bidirectionally
- **Collaborative Editing**: Integration with Nextcloud Office for document collaboration
- **Calendar & Contacts**: CalDAV and CardDAV support for calendar/contact synchronization
- **User Management**: Multi-user support with permissions and sharing capabilities
- **Background Jobs**: Cron job runs every 5 minutes for maintenance tasks
- **Health Monitoring**: Push-based monitoring for background job completion
- **Logging**: Centralized logs via Promtail to Loki monitoring stack

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL database for storing user data, files metadata, and configuration
- **Backbone**: Traefik for HTTPS termination and hostname routing
- **Monitoring** (optional): Health check monitoring and log aggregation

### Database Details

Nextcloud uses PostgreSQL for:

- User accounts and permissions
- File metadata and sharing information
- Calendar entries and event data
- Contact information
- Application configuration

## Network Configuration

- **internal network**: Internal communication with Redis
- **web network**: Exposed via Traefik for HTTPS access
- **db network**: Database connectivity
- **ldap network**: LDAP authentication support (optional)

## Security & Configuration

- **Redis Caching**: Improves performance for concurrent users
- **Custom Configuration**: Extra config via `extra.config.php`
- **CORS Headers**: Custom headers for browser security
- **Frame Options**: Configured for proper framing policies
- **Health Checks**: Status endpoint monitored at `/status.php`

## Deployment Notes

- Data directory `/mnt/storage/nextcloud/config/` contains configuration and user data
- Container runs with UID/GID 33 (www-data user)
- Background jobs automated via cron for maintenance, indexing, and sync
- Uptime Kuma monitors both the health status endpoint and background job execution
- Configuration is preserved across restarts via mounted volumes

## User-Facing Features

- **Web Interface**: File manager with drag-and-drop support
- **Desktop Client**: Sync folders on Windows, macOS, Linux
- **Mobile Apps**: iOS and Android apps for mobile access
- **CalDAV/CardDAV**: Calendar and contact synchronization with external clients
- **Collaborative Editing**: Edit documents together with other users
- **Sharing**: Share files and folders with other users or public links
- **Activities**: Track file changes and collaborations

## Related Documentation

Nextcloud integrates with the Monitoring stack for health monitoring and uses Databases for data persistence.
