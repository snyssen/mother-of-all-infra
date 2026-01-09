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
