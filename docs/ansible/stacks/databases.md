# Databases Stack

## Overview

The **Databases** stack provides centralized database services for the self-hosted infrastructure. It runs **PostgreSQL**, the primary relational database engine, along with **pgAdmin** for web-based database management and automated backup utilities.

## Components

### PostgreSQL

- **Image**: `postgres:16.11`
- **Purpose**: Primary relational database server
- **Container Name**: `postgres`
- **Port**: `127.0.0.1:5432` (local access only)

### pgAdmin

- **Image**: `dpage/pgadmin4:9.11`
- **Purpose**: Web-based PostgreSQL management interface
- **Container Name**: `pgadmin`
- **Access**: `https://pgadmin.{{ main_domain }}`
- **Features**: OAuth2 authentication, backup storage browser

### Postgres Backups

- **Image**: `prodrigestivill/postgres-backup-local:16-alpine`
- **Purpose**: Automated PostgreSQL backups
- **Container Name**: `postgres_backups`
- **Schedule**: Every 4 hours at 30 minutes past the hour (30 */4 * * *)
- **Format**: Custom PostgreSQL format (compatible with pg_restore)

## Key Features

- **Data Persistence**: PostgreSQL data stored in `{{ docker_mounts_directory }}/databases/postgres/data/`
- **Backup Management**: Automatic daily backups to `/mnt/storage/backups/postgres/`
- **Multi-Database Support**: Configured for multiple databases used by various services
- **Health Monitoring**: Backup jobs integrated with Uptime Kuma monitoring via healthcheck webhooks
- **Local Access Only**: PostgreSQL port exposed only on 127.0.0.1 for security

## Used By (Dependent Stacks)

Services that depend on the Databases stack:

- **Nextcloud**: Stores user data, calendars, contacts, files metadata
- **Immich**: Stores photo metadata and library information
- **Paperless**: Stores document metadata and index
- **Speedtest Tracker**: Stores network speed test results
- **Matrix**: Stores chat messages and user data
- **Dawarich**: Stores location tracking data
- **Various custom applications**: Any service requiring persistent relational data

## Network Configuration

- **db network**: Internal network connecting database services
- **web network**: pgAdmin is exposed via the web network and Traefik

## Deployment Notes

- Must be deployed before any service that requires a database
- Backup credentials are configured via environment variables
- Databases must be pre-created or initialized by dependent services
- pgAdmin is protected by Traefik middleware (typically OAuth2/Authelia)
- Storage volumes are shared with the backup system for archive access
