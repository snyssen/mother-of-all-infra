# Monitoring Stack

## Overview

The **Monitoring** stack provides observability and visualization of the infrastructure through metrics collection, log aggregation, and interactive dashboards. It includes **Prometheus** for metrics, **Grafana** for visualization, **Loki** for log aggregation, and **Uptime Kuma** for service availability monitoring.

## Components

### Prometheus

- **Image**: `quay.io/prometheus/prometheus:v3.9.1`
- **Purpose**: Metrics collection and storage
- **Container Name**: `prometheus`
- **Access**: `https://prometheus.{{ main_domain }}`
- **Data Retention**: 1 year

### Grafana

- **Image**: `grafana/grafana-oss:12.3.1`
- **Purpose**: Metrics visualization and dashboards
- **Container Name**: `grafana`
- **Access**: `https://grafana.{{ main_domain }}`

### Loki

- **Image**: Configured via Grafana Alloy
- **Purpose**: Log aggregation and storage
- **Configuration**: `/{{ docker_mounts_directory }}/monitoring/loki/loki-config.yaml`

### Uptime Kuma

- **Purpose**: Service availability and health monitoring
- **Access**: `https://uptime.{{ main_domain }}`
- **Integration**: Provides push-based health check endpoints for services

## Key Features

- **Metrics Collection**: Scrapes Prometheus endpoints from all monitored services
- **Custom Recording Rules**: Node-level recording rules in `node_rules.yml`
- **Log Aggregation**: Centralized log collection via Loki and Promtail
- **Service Monitoring**: HTTP, JSON-query, and push-based monitors
- **Historical Data**: 1-year retention of metrics for long-term trend analysis
- **Prometheus Metrics Export**: Traefik metrics are scraped for API gateway insights

## Used By

Multiple stacks report metrics and logs to the Monitoring stack:

- **Nextcloud**: Exports health status and background job completion
- **Minecraft**: Exports server performance metrics
- **Streaming** (Jellyfin): Performance and transcode metrics
- **Matrix**: Server performance and federation metrics
- **Any service with Prometheus exporters**: Automatically discovered via labels

## Network Configuration

- **monitoring network**: Internal network for monitoring components
- **web network**: Grafana and Prometheus dashboards exposed via Traefik

## Deployment Notes

- Deploy after Backbone stack for Traefik metrics integration
- Prometheus configuration is templated from `prometheus.yml` and `node_rules.yml`
- Loki requires specific ownership (UID 10001)
- Uptime Kuma uses root permissions (known limitation)
- Services register monitors dynamically via Ansible
- Data stored in `/mnt/storage/prometheus/` for persistence

## Related Documentation

Services can export metrics via Prometheus endpoints and are discovered through Traefik labels.
