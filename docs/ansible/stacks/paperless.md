# Paperless Stack

## Overview

The **Paperless** stack provides a self-hosted document management and archive system. It digitizes paper documents, manages PDFs, and makes them fully searchable through OCR. It replaces services like Evernote and Notion for document organization while offering better privacy and control.

## Components

### Paperless NGX

- **Image**: `ghcr.io/paperless-ngx/paperless-ngx:2.20.3`
- **Purpose**: Document scanning, OCR, and management
- **Container Name**: `paperless`
- **Access**: `https://paperless.{{ main_domain }}`
- **Storage**: `/mnt/storage/paperless/`

### Paperless Redis

- **Image**: `redis:8.4.0`
- **Purpose**: Caching and task queue
- **Container Name**: `paperless_redis`
- **Memory Limit**: 12MB

### Paperless Gotenberg

- **Purpose**: PDF generation and processing
- **Container Name**: `paperless_gotenberg`

### Paperless Tika

- **Purpose**: Document format conversion and extraction
- **Container Name**: `paperless_tika`

## Key Features

- **Document OCR**: Convert scanned PDFs to searchable text
- **Auto-Tagging**: Automatic classification using machine learning
- **Full-Text Search**: Search across all documents and extracted text
- **Consumption**: Monitor watch folder for new documents
- **Thumbnails**: Generate previews for quick browsing
- **Export**: Export documents and archive
- **Multi-User**: Support for multiple users with separate libraries
- **Barcode Recognition**: Separate documents using barcodes
- **Backup Integration**: Daily automated backups

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL database for document metadata and user accounts
- **Backbone**: Traefik for HTTPS termination
- **Monitoring** (optional): Service health monitoring

## Network Configuration

- **internal network**: Internal communication between Paperless components
- **web network**: Exposed via Traefik for web access
- **db network**: Database connectivity

## Storage

- **Documents Directory**: `/mnt/storage/paperless/` - stores all documents and thumbnails
- **Backups**: Automated daily backups configured via role
- **Redis Data**: `{{ docker_mounts_directory }}/paperless/redis/`

## Document Processing Pipeline

1. **Consumption**: Watch folder monitors for new PDFs
2. **Processing**: Extract text via Tika, generate thumbnails via Gotenberg
3. **OCR**: Extract searchable text from scanned documents
4. **Indexing**: Index documents for full-text search
5. **Storage**: Archive in organized structure

## Deployment Notes

- Paperless depends on Redis for task queue and Gotenberg/Tika for document processing
- Health checks verify service availability every 30 seconds
- Container restarts if health check fails after 5 retries
- Storage volumes are mounted for document persistence
- Database must be pre-created with appropriate user credentials
- Multiple document formats supported: PDF, PNG, JPEG, TIFF, etc.

## User-Facing Features

- **Web Interface**: Browse and search documents
- **Document Upload**: Drag-and-drop or folder watch import
- **Tagging**: Manual and automatic tag assignment
- **Collections**: Organize documents into collections
- **Search**: Full-text search across document content
- **Export**: Download documents in various formats
- **Sharing**: Share documents with other users
- **Workflow**: Automate processing with matching rules

## Related Documentation

Paperless integrates with the Monitoring stack for health checks and uses the Databases stack for metadata storage.
