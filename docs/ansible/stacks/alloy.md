# Alloy Stack

## Overview

The **Alloy** stack provides telemetry collection and log aggregation for the monitoring infrastructure. Grafana Alloy (formerly Loki Promtail) is a lightweight agent that collects logs from containers and systems, forwarding them to the Loki log aggregation service in the Monitoring stack.

## Components

### Grafana Alloy

- **Image**: `grafana/alloy:v1.12.1`
- **Purpose**: Telemetry agent for log and metrics collection
- **Container Name**: `alloy`
- **Configuration**: `/etc/alloy/config.alloy`
- **HTTP Server**: Port 12345 (health checks and metrics)

## Key Features

- **Log Collection**: Collects logs from Docker containers
- **Container Metrics**: Gathers container performance metrics
- **System Logs**: Access to `/var/log` files
- **Docker Integration**: Direct access to Docker container directories
- **Lightweight**: Minimal resource overhead
- **Configurable**: Flexible Alloy configuration language
- **Health Endpoint**: `/healthy` endpoint for monitoring

## Configuration

### Log Sources

- **Docker Container Logs**: Collected from `/var/lib/docker/containers/`
- **System Logs**: Access to `/var/log/` for system-level logs
- **Custom Sources**: Additional log sources configurable in `alloy-config.alloy`

### Memory Limit

- **Allocation**: 2GB (configurable based on log volume)
- **Auto-scaling**: Can be adjusted for lighter/heavier workloads

## Dependencies

### Related Stacks

- **Monitoring**: Sends collected logs to Loki service
- Works in conjunction with Prometheus for complete observability

## Network Configuration

- **http**: Port 12345 exposed for health checks and metrics
- **Docker Access**: Mounts Docker socket for container discovery

## Storage & Mounts

- **Configuration**: `/etc/alloy/config.alloy` - Alloy configuration file
- **System Logs**: `/var/log/` (read-only) - system log files
- **Docker Containers**: `/var/lib/docker/containers/` (read-only) - container logs

## Security Considerations

- **Read-Only Mounts**: Logs mounted as read-only for safety
- **Docker Socket**: Can read all container logs (requires trust)
- **User Permissions**: Runs with Docker access for container inspection

## Deployment Notes

- Typically deployed with or after Monitoring stack
- Requires read access to Docker containers and system logs
- Health checks validate service availability
- Can be restarted without affecting collected services
- No persistent storage required (transient logs)

## Performance Considerations

- **Memory Usage**: 2GB allocation for log buffering
- **CPU**: Minimal CPU footprint for collection
- **Disk I/O**: No disk writes for normal operation
- **Network**: Sends logs to Loki via network

## Monitoring Integration

- **Loki Backend**: Sends collected logs to Loki in Monitoring stack
- **Prometheus Metrics**: Exports collection metrics
- **Health Endpoint**: Available at `http://alloy:12345/healthy`

## Use Cases

- **Centralized Logging**: All container logs in one place
- **Troubleshooting**: Search and analyze logs across services
- **Performance Analysis**: Identify slow operations in logs
- **Audit Trail**: Keep historical logs for compliance
- **Pattern Detection**: Find recurring issues or errors

## Related Documentation

Alloy is part of the Monitoring stack ecosystem and sends data to Loki for log aggregation and Prometheus for metrics.
