# Speedtest Tracker Stack

## Overview

The **Speedtest Tracker** stack monitors your internet connection speed over time. It runs automated network speedtests at regular intervals and stores the results for historical analysis and visualization, helping you track ISP performance and identify connectivity issues.

## Components

### Speedtest Tracker

- **Image**: `lscr.io/linuxserver/speedtest-tracker:1.13.4`
- **Purpose**: Automated speedtest scheduler and web interface
- **Container Name**: `speedtest-tracker`
- **Access**: `https://speedtest-tracker.{{ main_domain }}`
- **Public Dashboard**: `https://speedtest-tracker.{{ main_domain }}/dashboard` (public access)

### Database Backend

- **Database**: PostgreSQL (from Databases stack)
- **Database Name**: `speedtest_tracker`
- **Purpose**: Store all test results and statistics

## Key Features

- **Automated Speedtests**: Runs network speedtests on a configured schedule
- **Historical Data**: Maintains complete history of all speed tests
- **Statistics**: Calculate averages, trends, and outliers
- **Public Dashboard**: Share results with public link (optional)
- **Server Selection**: Test against specific speedtest servers
- **Email Notifications**: Alert on significant speed changes
- **Timezone Support**: Results displayed in local timezone
- **Data Pruning**: Automatic cleanup of old results (configurable)

## Configuration

### Speedtest Schedule

- **Default**: Every 30 minutes (30 * * * *)
- **Customizable**: Via environment variable `SPEEDTEST_SCHEDULE`

### Server Selection

- **Specific Servers**: Can test against selected Speedtest servers
- **Default Servers**: Uses Ookla Speedtest server pool
- **Custom Server List**: `SPEEDTEST_SERVERS` environment variable

### Email Integration

- **SMTP Configuration**: Sends notifications via configured SMTP
- **Alert Triggers**: Notify when speed drops below threshold
- **Email From**: `speedtest-tracker@{{ main_domain }}`

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL for storing test results
- **Backbone**: Traefik for HTTPS access
- **Monitoring** (optional): Can be configured for alerting

## Storage

- **Database**: PostgreSQL stores all test results and statistics
- **Configuration**: Application settings and email templates
- **Results Retention**: Configurable pruning policy

## Use Cases

- **ISP Performance Monitoring**: Track your internet provider's performance
- **Troubleshooting**: Identify when speed drops occur
- **Historical Trends**: Analyze speed patterns over weeks/months
- **SLA Verification**: Verify your ISP meets promised speeds
- **Network Changes**: Measure impact of network changes
- **Public Accountability**: Share results to compare with others

## Deployment Notes

- Requires PostgreSQL database
- SMTP configuration needed for email notifications
- Public dashboard can be shared without authentication
- Speedtest requires active internet connection
- Results include download, upload, and latency metrics
- Timezone converted to local time for display
- Data pruning prevents database from growing unbounded

## Monitoring

- Health checks via HTTP requests to the web interface
- Can integrate with Uptime Kuma for monitoring
- Email alerts for significant speed changes
- Database monitoring for result storage

## Related Documentation

Speedtest Tracker integrates with the Databases stack for historical data storage and Backbone for web access.
