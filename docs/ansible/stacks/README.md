# Software Stacks Documentation

This directory contains comprehensive documentation for all software stacks deployed in the self-hosted infrastructure. Each stack is a collection of containerized services that work together to provide specific functionality.

## Stack Categories

### Core Infrastructure

These stacks provide the foundational services that other stacks depend on:

- **[Backbone](backbone.md)**: Reverse proxy, HTTPS/TLS termination, and routing (Traefik)
- **[Databases](databases.md)**: PostgreSQL database server with backups and web management
- **[Monitoring](monitoring.md)**: Prometheus, Grafana, Loki, and Uptime Kuma for observability

### Productivity & Collaboration

These stacks focus on personal productivity, file management, and team communication:

- **[Nextcloud](nextcloud.md)**: File synchronization, calendar, contacts, and collaboration
- **[Syncthing](syncthing.md)**: Decentralized peer-to-peer file synchronization
- **[Matrix](matrix.md)**: Federated messaging, real-time communication, and bridges
- **[Paperless](paperless.md)**: Document scanning, OCR, and digital archival

### Entertainment & Media

These stacks handle media storage, streaming, and gaming:

- **[Streaming](streaming.md)**: Jellyfin media server for movies, TV shows, music, and photos
- **[Minecraft](minecraft.md)**: Self-hosted Minecraft Java Edition server with live map

### Additional Stacks

Other specialized stacks providing specific services (see individual files for details):

- **actual-budget**: Personal finance and budgeting
- **alloy**: Grafana Alloy for telemetry collection
- **backrest**: Database backup management
- **cadvisor**: Container metrics and monitoring
- **crowdsec**: Security and threat detection
- **dashboard**: Personal dashboard/homepage
- **dawarich**: Location tracking and history
- **ddns**: Dynamic DNS client
- **foundryvtt**: Foundry Virtual Tabletop for RPG games
- **garage**: S3-compatible object storage and web UI for binary caching
- **immich**: Photo and video management (self-hosted Google Photos)
- **ntfy**: Push notifications
- **personal-website**: Static website hosting
- **quartz**: Note-taking and knowledge base
- **rallly**: Meeting planning and polling
- **recipes**: Recipe management
- **rest**: REST API services
- **semaphore**: Ansible UI and automation
- **sharkey**: Federated social media
- **skyrim-together**: Skyrim multiplayer mod server
- **s-pdf**: PDF manipulation tools
- **speedtest**: Network speedtest client
- **speedtest-tracker**: Network speedtest history and trends
- **team-wiki**: Team knowledge base
- **unifi**: UniFi network controller for WiFi management

## Stack Dependencies

### Dependency Tree

```
Backbone (Traefik)
├── Used by all web-based stacks for HTTPS/routing
└── Routes traffic to:
    ├── Monitoring (Prometheus, Grafana, Uptime Kuma)
    ├── Databases (pgAdmin)
    ├── Nextcloud
    ├── Immich
    ├── Paperless
    ├── Streaming (Jellyfin)
    ├── Matrix
    ├── Minecraft (Dynmap)
    └── ... and many others

Databases (PostgreSQL)
├── Nextcloud (user data, files, calendars, contacts)
├── Immich (photo metadata)
├── Paperless (document metadata)
├── Speedtest Tracker (results history)
├── Matrix (messages, federation, accounts)
└── Other services (as needed)

Monitoring (Prometheus, Grafana, Loki, Uptime Kuma)
├── Collects metrics from:
│   ├── Nextcloud (health, background jobs)
│   ├── Minecraft (performance)
│   ├── Streaming (transcoding, playback)
│   └── Other services with Prometheus exporters
└── Provides:
    ├── Historical metrics (1 year retention)
    ├── Service health monitoring
    └── Log aggregation via Loki
```

### Critical Dependencies

1. **Backbone** must be deployed first
   - Nearly all other stacks depend on it for public HTTP(S) access
   - Provides hostname-based routing and SSL/TLS termination

2. **Databases** must be deployed early
   - Required by: Nextcloud, Immich, Paperless, Speedtest Tracker, Matrix, and others
   - Must be initialized before dependent services

3. **Monitoring** provides observability
   - Optional but recommended for all deployments
   - Collects metrics, logs, and health status
   - Enables issue detection and performance tracking

## Deployment Order

Recommended deployment sequence:

1. **Backbone** - Core routing and HTTPS
2. **Databases** - Database infrastructure
3. **Monitoring** - Observability
4. **Application Stacks** (in any order after above):
   - Nextcloud
   - Immich
   - Paperless
   - Streaming
   - Matrix
   - Minecraft
   - Syncthing
   - And others as needed

## Network Architecture

### Docker Networks

- **web**: External network for public/Traefik-exposed services
- **internal**: Internal services communication (Redis, caches)
- **db**: Database network for PostgreSQL connections
- **monitoring**: Monitoring components (Prometheus, Loki, Grafana)
- **bridges**: Matrix bridge services
- **ldap**: LDAP/authentication services
- **lan**: Local network communication for discovery

### Service Communication

- **Inter-service**: Services communicate via Docker networks using container names as hostnames
- **External Access**: All public-facing services routed through Backbone (Traefik)
- **Database Access**: Services connect to PostgreSQL via `db` network
- **Metrics**: Services export Prometheus metrics on local ports scraped by Prometheus
- **Logs**: Services send logs via Promtail to Loki for centralized log aggregation

## Configuration & Customization

### Environment Variables

Stacks use templated configuration with Ansible variables:

- `{{ main_domain }}`: Base domain (e.g., example.com)
- `{{ iana_timezone }}`: Timezone for services
- `{{ docker_mounts_directory }}`: Base path for container volumes
- `{{ ansible_user_uid }}/{{ ansible_user_gid }}`: User/group IDs
- Service-specific variables for credentials and settings

### Persistent Data

- **Application Data**: Stored in `/mnt/storage/` for long-term persistence
- **Container Volumes**: Stored in `{{ docker_mounts_directory }}/` (typically `/opt/docker/mounts/`)
- **Backups**: Automated backups in `/mnt/storage/backups/`

## Management & Operations

### Playbooks

- `stacks-deploy.ansible.yml`: Deploy one or more stacks
- `stacks-manage.ansible.yml`: Manage stack state (start, stop, restart)
- Backup playbooks for database and file backups
- Service-specific playbooks for custom operations

### Health Monitoring

- **Uptime Kuma**: Monitors service availability
- **Prometheus**: Collects detailed metrics
- **Grafana**: Visualizes metrics in dashboards
- **Healthchecks**: Each stack includes health check configuration

## Security Considerations

- **Network Isolation**: Services isolated in Docker networks
- **HTTPS Only**: All public traffic encrypted via Backbone stack
- **Authentication**: Services protected via Traefik middleware (Authelia for OAuth2)
- **Backups**: Regular automated backups with encryption support
- **Secrets Management**: Credentials managed via Ansible vault

## Related Documentation

- See `ansible/README.md` for playbook and deployment information
- See `ansible/roles/` for detailed role implementations
- See `docs/backups.md` for backup and disaster recovery information
