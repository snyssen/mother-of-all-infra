# Ntfy Stack

## Overview

The **Ntfy** stack provides a simple, self-hosted push notification service. It enables sending browser, phone, and desktop notifications to yourself or sharing notification channels with others for collaborative alerts and real-time updates.

## Components

### Ntfy Server

- **Image**: `ntfy` (self-hosted ntfy.sh implementation)
- **Purpose**: Push notification hub and web interface
- **Container Name**: `ntfy`
- **Access**: `https://ntfy.{{ main_domain }}`
- **API**: Available for external notification sources

## Key Features

- **Web Interface**: Simple topic-based notification management
- **Multiple Clients**: Browser notifications, mobile apps, webhooks, APIs
- **Topics**: Public or private notification topics/channels
- **Subscription**: Subscribe to topics and receive notifications
- **Retention**: Store recent notifications for later retrieval
- **Scheduling**: Send notifications at specific times
- **Scripting**: API for integration with automation tools
- **No Authentication Required** (by default): Simple use without accounts

## Use Cases

- **Home Automation**: Alerts from smart home systems
- **Backup Notifications**: Get alerts when backups complete
- **Monitoring Alerts**: Receive system and service alerts
- **Cronjob Status**: Notifications for scheduled task completion
- **Team Updates**: Share notifications across teams
- **Health Checks**: Integration with monitoring systems
- **Mobile Alerts**: Receive notifications on phone

## Dependencies

### Optional Stacks

- **Backbone**: Traefik for HTTPS access (recommended)

## Storage

- **Notification History**: Recent notifications stored in memory
- **Configuration**: Application settings

## Network Configuration

- **web network**: Public access via Traefik

## API Integration

### Sending Notifications

- **HTTP POST**: Send notifications to topics via HTTP
- **Webhook Support**: Trigger notifications from webhooks
- **Email Integration**: Receive notifications via email
- **Command Line**: `curl` commands for easy integration

### Example Integrations

- **Ansible**: Ansible tasks can send ntfy notifications
- **Cronjobs**: Automated tasks can alert on completion
- **Monitoring**: Prometheus alertmanager integration
- **Webhooks**: GitHub, GitLab, other services

## Security Considerations

- **Public Topics**: Anyone with URL can subscribe
- **Private Topics**: Access control via authentication
- **HTTPS**: All communication encrypted
- **Rate Limiting**: Prevent abuse and spam

## Deployment Notes

- Lightweight service with minimal resource requirements
- No database required (notifications stored in memory)
- Simple configuration via environment variables
- Perfect for simple, targeted notifications
- Can be used alongside more complex monitoring systems

## User-Facing Features

- **Web UI**: Subscribe to and manage topics
- **Mobile Apps**: iOS and Android apps available
- **Browser Notifications**: Native browser notification support
- **Topic Management**: Create public or private topics
- **History**: View recent notifications for a topic
- **CLI**: Command-line tools for scripting

## Related Documentation

Ntfy is a simple notification service that integrates well with the Backbone stack for web access and works alongside the Monitoring stack for alerting.
