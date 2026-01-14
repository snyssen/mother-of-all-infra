# Attic Stack

## Overview

The **Attic** stack is a self-hosted, high-performance binary cache for Nix. It stores pre-built Nix packages and derivations, allowing fast retrieval instead of rebuilding from source. This dramatically reduces build times across your infrastructure.

## Components

### Attic Server

- **Image**: `ghcr.io/zhaofengli/attic:latest`
- **Purpose**: Binary cache server for Nix packages
- **Container Name**: `attic`
- **Port**: `8080` (internal)
- **Access**: `https://attic.{{ main_domain }}`
- **Storage Backend**: Local filesystem at `/mnt/storage/attic/storage`
- **Database Backend**: PostgreSQL (shared with Databases stack)

## Key Features

- **Multi-Store Support**: Manages multiple Nix caches (stores) independently
- **Content-Addressed Storage**: Deduplicates identical content across caches
- **JWT Authentication**: Token-based authentication for secure access
- **Garbage Collection**: Automatic cleanup of old entries (30-day retention)
- **Data Chunking**: Intelligent chunking for efficient storage and deduplication
  - Minimum chunk size: 16 KiB
  - Average chunk size: 64 KiB (65536 bytes)
  - Maximum chunk size: 256 KiB (262144 bytes)
  - Threshold: Files ≥64 KiB are chunked

## Configuration

### Data Storage

- **Attic Configuration**: `/mnt/storage/attic/attic.toml`
- **Cache Storage**: `/mnt/storage/attic/storage`
- **Permissions**: Mode `0600` for config (read/write by attic user only)

### JWT Authentication

The Attic server uses RS256 (RSA) keys for JWT token signing:

- **Private Key**: Loaded from template `jwtRS256.key` and base64-encoded in config
- **Public Key**: Available in `jwtRS256.key.pub` for client verification
- **Key Generation**: Done during Ansible deployment via templates

### Database Integration

- **User**: `attic` (created in Databases stack)
- **Database**: `attic` (PostgreSQL)
- **Host**: `postgres` (internal Docker network)
- **Port**: `5432`
- **Password**: `{{ attic__postgres_password }}` (from vault)

## Stores (Caches)

The default configuration supports multiple stores, primarily:

- **Store Name**: `snyssen-infra`
- **Description**: Primary cache for mother-of-all-infra builds

Each store maintains independent package metadata and storage while sharing the backend infrastructure.

## Token Management

### Generating JWT Tokens

Tokens allow CLI tools and CI/CD systems to authenticate with your Attic cache. Generate tokens on the server:

```bash
# Generate a full-access token (recommended for development)
docker exec attic atticadm make-token -f /attic/attic.toml \
  --sub your-username \
  --validity 365d \
  --create-cache "snyssen-*" \
  --push "snyssen-*" \
  --pull "snyssen-*"
```

Replace `your-username` with the token subject (e.g., `snyssen`, `ci-github-actions`).

#### Token Parameters Explained

- `--sub`: Token subject/username (used for logging and tracking)
- `--validity 365d`: Token expiry (365 days from creation)
- `--create-cache "snyssen-*"`: Permission to create caches matching pattern `snyssen-*`
- `--push "snyssen-*"`: Permission to push packages to `snyssen-*` caches
- `--pull "snyssen-*"`: Permission to pull packages from `snyssen-*` caches

### Example: GitHub Actions Token

Generate a restricted token for CI/CD:

```bash
docker exec attic atticadm make-token -f /attic/attic.toml \
  --sub github-actions-ci \
  --validity 365d \
  --push "snyssen-*" \
  --pull "snyssen-*"
```

This token can push and pull but cannot create new caches.

### Using Tokens

Configure your Nix CLI or CI/CD with the token:

```bash
# Login to Attic (stores credentials in ~/.config/attic/)
attic login snyssen-infra https://attic.{{ main_domain }} <TOKEN>

# Or use environment variable
export ATTIC_TOKEN=<TOKEN>
```

## Relations to Other Stacks

### Depends On

- **Databases Stack**: PostgreSQL for metadata storage
- **Backbone Stack**: Traefik for HTTPS routing and SSL/TLS termination

### Used By

- **GitHub Actions**: CI/CD pipeline builds (see `.github/workflows/build-and-cache-flake.yml`)
- **All NixOS Hosts**: Use Attic as primary substituter for package retrieval
- **Developers**: Local development machines can configure Nix to use cache

## Network Integration

- **Docker Network**: `web` (connected to Traefik)
- **Database Network**: `db` (connected to PostgreSQL)
- **Hostname**: `attic.{{ main_domain }}`
- **TLS**: Automatic via Traefik + Let's Encrypt

## Security Considerations

### Access Control

- **Token-Based**: Only authenticated requests with valid JWT tokens
- **Cache Pattern Matching**: Tokens specify which caches they can access
- **Expiry**: Set reasonable token validity (365 days recommended for CI tokens)
- **Rotation**: Generate new tokens periodically and retire old ones

### Data Protection

- **Configuration File**: Mode `0600` (readable/writable by owner only)
- **Database Password**: Stored in vault (SOPS-encrypted)
- **Storage Directory**: Owned by Attic container user, restricted permissions
- **TLS Required**: All traffic encrypted via HTTPS

## Deployment Notes

- Attic deploys to the same server as Databases and Backbone stacks
- Storage directory must exist and be writable by the container
- PostgreSQL must be running before Attic starts (handled by docker-compose dependencies)
- Public cache key needed in Nix configuration (see `nix/modules/nixos/cache.nix`)

## Monitoring and Maintenance

### Logs

View Attic logs:

```bash
docker logs -f attic
```

### Storage Usage

Check cache storage size:

```bash
du -sh /mnt/storage/attic/storage/
```

### Database Backups

Attic database is backed up automatically via the Databases stack backup routine.

### Garbage Collection

The Attic service automatically cleans up entries older than 30 days. This is configurable via the `[garbage-collection]` section in `attic.toml`.

## Troubleshooting

### Cache Not Accessible

- Verify Traefik is routing correctly: `curl https://attic.{{ main_domain }}`
- Check Attic logs: `docker logs attic`
- Verify database connection: `docker exec attic /bin/sh -c 'pg_isready -h postgres'`

### Token Generation Fails

- Verify Attic container is running: `docker ps | grep attic`
- Check config file permissions: `ls -l /mnt/storage/attic/attic.toml`
- Ensure private key template was rendered: `docker exec attic test -f /attic/attic.toml`

### Push/Pull Permissions Denied

- Verify token has correct permissions (check `--push`/`--pull` flags)
- Confirm cache name matches allowed pattern (e.g., `snyssen-*`)
- Check token hasn't expired: `attic token list` (requires admin token)

## Integration Example: GitHub Actions

The `.github/workflows/build-and-cache-flake.yml` workflow:

1. Triggers on `flake.lock` changes
2. Builds each NixOS host configuration
3. Authenticates with Attic using CI token
4. Pushes build outputs to cache
5. Future builds use cached packages

See `.github/workflows/build-and-cache-flake.yml` for full workflow definition.

## Related Documentation

- **Attic Project**: [https://github.com/zhaofengli/attic](https://github.com/zhaofengli/attic)
- **Nix Cache Configuration**: See `nix/modules/nixos/cache.nix`
- **Deployment Guide**: See `ATTIC_DEPLOYMENT.md`
- **Databases Stack**: See `databases.md`
- **Backbone Stack**: See `backbone.md`
