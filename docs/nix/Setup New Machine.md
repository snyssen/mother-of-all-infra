# Setup a New Machine

This guide walks you through deploying a new NixOS machine using `nixos-anywhere`. The process is divided into three phases that happen in sequence:

## Process Overview

```
Admin Host              Target Machine              Admin Host
├─ Pre-Deployment      (Powered Off)
│  ├─ Create config
│  ├─ Generate SSH keys
│  ├─ Authorize age keys
│  ├─ Prepare credentials
│  └─ Validate flake
│
├─────────────────────────────────────────────────>
│                   Boot Live Environment
│                   Minimal Setup (~5 min)
│
│                  Run nixos-anywhere
│<─────────────────────────────────────────────────
│                   Automated Deployment
│                   (~20–60 min)
│                   Auto-reboot
│
└─ Post-Deployment    System Online
   ├─ Verify basics
   ├─ Setup cache (optional)
   └─ Commit config
```

## The Three Phases

### Phase 1: Pre-Deployment (15–30 minutes on admin host)

**What**: Prepare everything needed for deployment
**Where**: Admin host only (target not yet needed)
**See**: [Setup New Machine - Pre-Deployment](./Setup%20New%20Machine%20-%20Pre-Deployment.md)

Includes:
- Create NixOS configuration files
- Generate SSH keypairs for target
- Derive and authorize age keys in SOPS
- Prepare deployment credentials
- Validate flake builds

**Time required**: 15–30 minutes

### Phase 2: Deployment (30–90 minutes, alternating target/admin)

**What**: Boot target and run automated NixOS installation
**Where**: Target machine + admin host
**See**: [Setup New Machine - Deployment](./Setup%20New%20Machine%20-%20Deployment.md)

Includes:
- Boot target to NixOS minimal ISO
- Minimal live environment setup (~5 minutes)
- Run `nixos-anywhere` from admin host
- Automated partitioning, formatting, configuration
- Automatic reboot

**Time required**: 30–90 minutes (mostly automated)

### Phase 3: Post-Deployment (5–15 minutes on target)

**What**: Verify system and complete optional setup
**Where**: Target machine (and optional cache server)
**See**: [Setup New Machine - Post-Deployment](./Setup%20New%20Machine%20-%20Post-Deployment.md)

Includes:
- Verify system identity and networking
- Confirm secrets were decrypted
- Verify Tailscale connectivity
- Optional: Set up attic cache authentication
- Commit configuration to git

**Time required**: 5–15 minutes (mostly manual verification)

## Prerequisites

Before starting, ensure:

- Nix package manager installed on admin host
- This repository cloned and up to date
- You are in the devshell: `nix develop`
- For physical targets: Ability to boot NixOS minimal USB image
- For cloud VPS targets: IP address/hostname from provider
- Network connectivity between admin and target (during live environment)

## Quick Start

1. **Start here**: [Setup New Machine - Pre-Deployment](./Setup%20New%20Machine%20-%20Pre-Deployment.md)
2. **Then**: [Setup New Machine - Deployment](./Setup%20New%20Machine%20-%20Deployment.md)
3. **Finally**: [Setup New Machine - Post-Deployment](./Setup%20New%20Machine%20-%20Post-Deployment.md)

## Key Concepts

### Admin Host
The machine you are using to orchestrate the setup (usually your development laptop). Must have Nix installed.

### Target Host
The new NixOS machine being deployed. May have no operating system yet (bare metal) or be a VPS.

### Live Environment
The NixOS minimal ISO running in RAM on the target during deployment. Used by `nixos-anywhere` to partition disks and install NixOS. Discarded after reboot.

### SSH Keys
Keypairs generated on the admin host and staged for deployment on the target. Used for:
- Git operations and commit signing
- SSH connections to other machines
- Deriving age keys for SOPS secret decryption

Deleted from admin host immediately after successful deployment.

### Age Keys
Derived from SSH keys; used for encrypting/decrypting secrets with SOPS. The target's age key is authorized in `.sops.yaml` before deployment, allowing the target to decrypt its own secrets at boot time.

## Terminology

- **Admin host**: Development machine performing the setup orchestration
- **Target host**: The new NixOS machine being deployed
- **Deployment**: The automated process of installing and configuring the target
- **Pre-staging**: Preparing files and credentials on the admin host before deployment
- **Live environment**: NixOS minimal ISO running in RAM during deployment

## Related Documentation

- [Full Disk Encryption](./Full%20Disk%20Encryption.md): For LUKS configuration and keyfiles
- [Secrets Management with SOPS](./secrets-management.md): How secrets are encrypted/decrypted
- [NixOS Anywhere Documentation](https://nix-community.github.io/nixos-anywhere/)
