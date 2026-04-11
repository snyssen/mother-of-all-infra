# Network Overview

## DNS Setup

![Network diagram showing how DNS is resolved at different layers](./network.svg)

This setup ensures that HTTP path is always as direct as possible while ensuring safe access to services.

## Connection Flows by Client Type

### 1. Device from Internet (Unknown Device)

```mermaid
sequenceDiagram
    participant Unknown as Unknown Device
    participant PublicDNS as Public DNS
    participant Ingress as Ingress Server<br/>(46.226.104.72)
    participant TechDNS as Technitium DNS<br/>(100.70.229.74)
    participant AppServer as App Server<br/>Tailscale IP: 100.114.242.89<br/>LAN IP: 192.168.1.10

    Unknown->>PublicDNS: DNS Query: app.example.com
    PublicDNS-->>Unknown: Returns 46.226.104.72 (Ingress Server)

    Unknown->>Ingress: HTTP Request to 46.226.104.72
    Ingress->>TechDNS: DNS Query: app.example.com (on tailnet)
    TechDNS-->>Ingress: Returns 100.114.242.89 (App Server Tailscale IP)
    Ingress->>AppServer: Reverse proxy request via Tailscale
    AppServer-->>Ingress: HTTP Response
    Ingress-->>Unknown: HTTP Response (proxied)
```

### 2. Device from Internet with Tailscale (Personal Laptop)

```mermaid
sequenceDiagram
    participant Personal as Personal Laptop<br/>(Tailscale: 100.x.x.x)
    participant TechDNS as Technitium DNS<br/>(100.70.229.74)
    participant AppServer as App Server<br/>Tailscale IP: 100.114.242.89<br/>LAN IP: 192.168.1.10

    Personal->>TechDNS: DNS Query: app.example.com
    TechDNS-->>Personal: Returns 100.114.242.89 (App Server Tailscale IP)

    Personal->>AppServer: HTTP Request to 100.114.242.89 via Tailscale
    AppServer-->>Personal: HTTP Response
```

### 3. Device from LAN (Guest Computer)

```mermaid
sequenceDiagram
    participant Guest as Guest Computer<br/>(192.168.1.x)
    participant AdguardHome as Adguard Home<br/>(192.168.1.2)
    participant AppServer as App Server<br/>Tailscale IP: 100.114.242.89<br/>LAN IP: 192.168.1.10

    Guest->>AdguardHome: DNS Query: app.example.com
    AdguardHome-->>Guest: Returns 192.168.1.10 (App Server LAN IP)

    Guest->>AppServer: HTTP Request to 192.168.1.10 via LAN
    AppServer-->>Guest: HTTP Response
```

### 4. Device from LAN with Tailscale (Home Computer)

```mermaid
sequenceDiagram
    participant Home as Home Computer<br/>(192.168.1.x + Tailscale)
    participant TechDNS as Technitium DNS<br/>(100.70.229.74)
    participant AppServer as App Server<br/>Tailscale IP: 100.114.242.89<br/>LAN IP: 192.168.1.10

    Home->>TechDNS: DNS Query: app.example.com
    TechDNS-->>Home: Returns 100.114.242.89 (App Server Tailscale IP)

    Home->>AppServer: HTTP Request to 100.114.242.89 via Tailscale
    AppServer-->>Home: HTTP Response
```
