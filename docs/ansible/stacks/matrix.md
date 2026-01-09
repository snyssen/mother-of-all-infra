# Matrix Stack

## Overview

The **Matrix** stack provides a decentralized, federated messaging protocol implementation. Matrix enables real-time communication including instant messaging, group chat, and VoIP while maintaining privacy and interoperability with other Matrix servers. It replaces centralized messaging platforms like Discord or Slack with a self-hosted alternative.

## Components

### Synapse

- **Image**: `matrixdotorg/synapse:v1.144.0`
- **Purpose**: Matrix homeserver - core messaging and federation
- **Container Name**: `synapse`
- **Access**: `https://matrix.{{ main_domain }}`
- **Configuration**: `/mnt/storage/matrix/synapse/homeserver.yaml`

### Matrix Authentication Service (MAS)

- **Image**: `ghcr.io/element-hq/matrix-authentication-service:1.8.0`
- **Purpose**: OAuth2 authentication and account management
- **Container Name**: `matrix_mas`
- **Configuration**: `/mnt/storage/matrix/mas/mas_config.yaml`

### Bridge Services

- **Platforms**: Multiple bridges configured for interoperability
- **Network**: `bridges` network for bridge components
- **Purpose**: Connect Matrix to other platforms (IRC, Telegram, Discord, etc.)

## Key Features

- **Federated Messaging**: Communicate with users on other Matrix servers
- **Encrypted Rooms**: End-to-end encryption for private rooms
- **User Accounts**: Manage multiple user accounts on the server
- **Room Management**: Create public or private chat rooms
- **Media Support**: Share images, videos, and files
- **Presence**: Show online/away status
- **Typing Indicators**: Real-time feedback of typing activity
- **Read Receipts**: Track message read status
- **Account Recovery**: OAuth2 integration for secure authentication
- **Bridge Support**: Connect to other messaging platforms

## Dependencies

### Required Stacks

- **Databases**: PostgreSQL for Synapse message history and account data
- **Backbone**: Traefik for HTTPS termination and routing
- **Monitoring** (optional): Service health monitoring

## Network Configuration

- **web network**: Public access via Traefik
- **db network**: Database connectivity for Synapse
- **bridges network**: Internal network for bridge services

## Storage

- **Synapse Data**: `/mnt/storage/matrix/synapse/` - messages, user data, media uploads
- **MAS Configuration**: `/mnt/storage/matrix/mas/` - authentication service configuration
- **Media**: Stored within Synapse data directory

## Security Features

- **OAuth2 Authentication**: Secure account management via MAS
- **Encryption Support**: End-to-end encryption for sensitive conversations
- **Server Federation**: Validates federation requests and certificates
- **Access Control**: Room permissions and user roles
- **Rate Limiting**: Prevent abuse and spam

## Deployment Notes

- Synapse requires PostgreSQL database
- Configuration file generated during deployment
- Matrix Authentication Service provides modern OAuth2 experience
- Server name configured for federation with other Matrix instances
- Media uploads stored on disk and accessible to authenticated users
- Bridge services connect to external messaging platforms
- Supports multiple concurrent client connections

## User-Facing Features

- **Web Client**: Element (formerly Riot) web interface
- **Mobile Apps**: Element and other Matrix clients for iOS/Android
- **Desktop Client**: Desktop applications for Windows, macOS, Linux
- **End-to-End Encryption**: Create encrypted rooms for sensitive conversations
- **Room Creation**: Create channels for group discussion
- **Direct Messages**: 1-on-1 encrypted or unencrypted messaging
- **File Sharing**: Upload and share files in rooms
- **Presence**: See who is online
- **Notifications**: Push notifications for new messages
- **Community Servers**: Join communities and explore public rooms

## Federation

The Matrix server can:

- Participate in the global Matrix federation
- Communicate with users on other homeservers
- Share rooms across server boundaries
- Support room aliases for easy discovery
- Validate federation requests for security

## Bridge Capabilities

Depending on configured bridges, users can:

- Bridge with IRC networks for legacy communication
- Connect to Telegram users
- Integrate with Discord servers
- Link other messaging platforms

## Related Documentation

Matrix integrates with the Databases stack for message storage and the Backbone stack for public access. Bridge services may have additional dependencies.
