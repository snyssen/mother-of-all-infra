# Minecraft Stack

## Overview

The **Minecraft** stack provides a self-hosted Minecraft Java Edition server with modern features, performance optimization, and web-based administration. It enables playing Minecraft with friends on your own server while maintaining full control over the world, plugins, and game rules.

## Components

### Minecraft Server

- **Image**: `itzg/minecraft-server:2026.1.0`
- **Purpose**: Paper-based Minecraft server with performance optimizations
- **Container Name**: `minecraft`
- **Server Type**: PAPER (production-grade fork with optimizations)
- **Minecraft Version**: 1.20.2
- **Access**: Direct connection on `minecraft.{{ main_domain }}:25565` or dynmap at `https://mc.{{ main_domain }}`
- **Storage**: `/mnt/storage/minecraft/`

### Dynmap

- **Purpose**: Web-based live map of the Minecraft world
- **Access**: `https://mc.{{ main_domain }}`
- **Port**: 8123 (internally)

## Key Features

- **Performance Optimization**: Paper server reduces lag and improves TPS (ticks per second)
- **World Generation**: Fully customizable world seed and generation settings
- **Plugins**: Support for Bukkit/Spigot/Paper plugins for extended functionality
- **Difficulty Settings**: Configurable game difficulty (Peaceful to Hard)
- **Player Whitelist**: Only allow specific players to join
- **Autopause**: Server pauses when no players connected (can be disabled)
- **EULA Acceptance**: Automatically accepts EULA during startup
- **Live Map**: Dynmap provides real-time web-based world map
- **Backup Integration**: World data backed up regularly

## Dependencies

### Required Stacks

- **Backbone**: Traefik for:
  - Dynmap web access at `https://mc.{{ main_domain }}`
  - TCP port 25565 routing for direct Minecraft connections
  - UDP multicast support for LAN discovery (if enabled)

### Optional Stacks

- **Monitoring**: Server performance and player metrics

## Network Configuration

- **internal network**: Local server communication
- **web network**: Dynmap web interface
- **monitoring network**: Performance metrics export

## Storage

- **World Data**: `/mnt/storage/minecraft/` - world files, player data, configuration
- **Persistent Across Restarts**: All data preserved in volume mounts
- **Server Properties**: Configuration via environment variables

## Server Configuration

- **EULA**: Automatically accepted during container startup
- **Difficulty**: Set via `MINECRAFT_DIFFICULTY` variable
- **Whitelist**: Players specified via `MINECRAFT_WHITELIST` variable
- **Memory**: 8GB allocated for server JVM
- **Max Tick Time**: Set to -1 (unlimited) to prevent watchdog kills
- **MOTD**: Custom message of the day shown in server browser

## Deployment Notes

- Server requires sufficient resources (CPU and RAM) for smooth gameplay
- 8GB memory allocated by default (adjustable)
- Autopause disabled due to Traefik routing complications (players connecting via Traefik may not register)
- Paper server automatically downloads on startup
- Server properties can be overridden via environment variables
- World data persists across container restarts
- Whitelist restricts access to specified players
- Dynmap generates live map at regular intervals

## Gameplay Features

- **Java Edition**: Full compatibility with Java Edition clients
- **Multiplayer**: Support for multiple concurrent players
- **Mods/Plugins**: Paper server compatible with Bukkit plugins
- **World Management**: Seed-based world generation, customizable biomes
- **Survival/Creative**: Both game modes supported
- **PvP**: Configurable player-vs-player combat
- **Commands**: Operator commands for administration
- **Chat**: In-game chat and communication

## Client Connection

Players connect to the Minecraft server using:

- **Direct Connection**: `minecraft.{{ main_domain }}` (port 25565)
- **Or**: Use the IP address and standard Minecraft port (25565)
- **Web Map**: Access live map at `https://mc.{{ main_domain }}`

## Performance Considerations

- Paper server reduces lag through performance optimizations
- Autopause disabled to avoid complications with Traefik routing
- Server will pause if no players are online (with autopause enabled)
- Dynmap updates periodically and requires disk space for map rendering

## Related Documentation

Minecraft integrates with the Backbone stack for network access and optionally with the Monitoring stack for performance tracking.
