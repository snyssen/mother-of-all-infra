# Dawarich Stack

## Overview

The **Dawarich** stack provides a self-hosted location tracking and history service. It tracks your geographic location over time and provides detailed analytics and visualization of your movements and travel patterns while keeping all data private on your own server.

## Components

### Dawarich Backend

- **Purpose**: Location tracking API and processing
- **Container Name**: `dawarich`
- **Access**: `https://dawarich.{{ main_domain }}`

### Dawarich Frontend

- **Purpose**: Web interface for viewing location history
- **Container Name**: `dawarich-frontend`
- **Access**: Via Traefik routing

### Dawarich Database

- **Backend**: PostgreSQL (from Databases stack)
- **Purpose**: Store location data points and user information

## Key Features

- **Location Tracking**: Automatic tracking of GPS coordinates over time
- **Timeline View**: Visualize travel history on interactive map
- **Statistics**: Analyze movement patterns, distance traveled, time at locations
- **Privacy**: All data stays on your server, no third-party access
- **Mobile Integration**: Mobile app or API for submitting location data
- **History Export**: Export location data in various formats
- **Location Clustering**: Identify frequently visited locations

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL for storing location history
- **Backbone**: Traefik for HTTPS access

## Storage

- **Location Data**: `/mnt/storage/dawarich/` - historical location points
- **Configuration**: Container configuration and API keys

## Use Cases

- **Travel Tracking**: Track trips and vacations
- **Activity Logging**: Record where you've been
- **Commute Analysis**: Analyze regular travel patterns
- **Memory**: Remember places you've visited
- **Statistics**: Calculate total distance and time traveled

## Deployment Notes

- Requires PostgreSQL database setup
- API endpoints for submitting location data
- Mobile apps available for automatic tracking
- Data retention configurable

## Related Documentation

Dawarich integrates with the Databases stack for data persistence and Backbone for web access.
