# Backbone Stack

## Overview

The **Backbone** stack is the core reverse proxy and entry point for all HTTP(S) traffic to the self-hosted infrastructure. It runs **Traefik**, a modern reverse proxy and load balancer that manages SSL/TLS certificates, routes traffic to various services, and provides API gateway capabilities.

## Components

### Traefik

- **Image**: `traefik:v3.6.6`
- **Purpose**: Reverse proxy, HTTP(S) router, and load balancer
- **Container Name**: `traefik`

## Key Features

- **HTTP/HTTPS Routing**: Routes requests based on hostnames and paths to appropriate backend services
- **SSL/TLS Management**: Automatic certificate generation and renewal via Let's Encrypt using DNS or HTTP challenges
- **Service Discovery**: Automatically discovers and routes to Docker containers with Traefik labels
- **API Dashboard**: Provides a web dashboard for monitoring routes and metrics
- **Protocol Support**:
  - HTTP/HTTPS for web services
  - UDP ports for specific protocols (Unifi, Jellyfin discovery, Syncthing, Minecraft, Skyrim Together)
  - TCP ports for custom protocols

## Network Exposure

The Backbone stack exposes the following ports:

- **80 (HTTP)**: Redirects to HTTPS
- **443 (HTTPS)**: Secure web traffic
- **3478 (UDP)**: Unifi STUN
- **10001 (UDP)**: Unifi AP discovery
- **8080 (TCP)**: Unifi device communication
- **25565 (TCP)**: Minecraft server
- **7359 (UDP)**: Jellyfin client discovery
- **22000 (TCP/UDP)**: Syncthing synchronization
- **21027 (UDP)**: Syncthing device discovery
- **10578 (UDP)**: Skyrim Together Reborn server

## Relations to Other Stacks

### Depends On

- **Docker Daemon**: Traefik monitors Docker events to discover services

### Used By

The Backbone stack is the entry point for nearly all web-based services in the infrastructure. Services depend on it for:

- Hostname-based routing
- SSL/TLS termination
- HTTP/HTTPS protocol support
- Metrics collection (Prometheus integration)

## Deployment Notes

- The Backbone stack must be deployed first as other services depend on it
- Certificates are stored at `{{ docker_mounts_directory }}/traefik/certs/`
- DNS API credentials are passed via environment variables
- The Docker socket is mounted to enable service discovery

## ACME Multi-Provider Configuration

Traefik ACME is configured with multiple resolvers so each domain can use its own DNS challenge provider.

- `backbone__acme_default_resolver`: resolver used as default on the `websecure` entrypoint
- `backbone__acme_domains`: domains and wildcard SANs, each mapped to a resolver
- `backbone__acme_resolvers`: resolver definitions (CA server, storage file, DNS provider, DNS resolver, propagation delay, environment variables)

### Current Mapping

- `main_domain` -> `le_main` (Dynu)
- `team_domain` -> `le_team` (Porkbun)

### Important Behavior

- EntryPoint default resolver is only one resolver. Domains that use a different provider must use an explicit router-level resolver.
- Mixed-domain router rules should be split into one router per domain so each router can set the right `tls.certresolver`.
- Wildcard certificates are requested per domain (`*.domain`) through DNS challenge.

### Adding A New Domain/Provider

1. Add a resolver entry in `backbone__acme_resolvers`.
2. Add provider credentials to the resolver `env` map.
3. Add a domain entry in `backbone__acme_domains` mapped to that resolver.
4. Ensure routers for that domain use the matching `tls.certresolver` when not using the entrypoint default.
