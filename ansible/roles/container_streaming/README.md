<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

**Table of Contents** _generated with [DocToc](https://github.com/thlorenz/doctoc)_

- [A note on the directory structure](#a-note-on-the-directory-structure)
  - [Server structure](#server-structure)
  - [Internal docker structure](#internal-docker-structure)
    - [torrents](#torrents)
    - [usenet](#usenet)
    - [servarr apps](#servarr-apps)
    - [Jellyfin](#jellyfin)
  - [Configurations](#configurations)
  - [Peertube Configuration](#peertube-configuration)
    - [Required Vault Variables](#required-vault-variables)
    - [Generating Secrets](#generating-secrets)
    - [Peertube Data Structure](#peertube-data-structure)
    - [Access](#access)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# A note on the directory structure

The directory structured follows the recommendations from the [servarr team](https://wiki.servarr.com/docker-guide#consistent-and-well-planned-paths) and [this guide](https://trash-guides.info/Hardlinks/How-to-setup-for/Docker/).

## Server structure

```txt
/mnt/storage/streaming
├── torrent
│  ├── movies
│  ├── music
│  └── tv
├── usenet
│  ├── movies
│  ├── music
│  └── tv
└── media
   ├── movies
   ├── music
   └── tv
```

## Internal docker structure

### torrents

```txt
/data
└── torrent
   ├── movies
   ├── music
   └── tv
```

### usenet

```txt
/data
└── usenet
   ├── movies
   ├── music
   └── tv
```

### servarr apps

```txt
/data
├── torrent
│  ├── movies
│  ├── music
│  └── tv
├── usenet
│  ├── movies
│  ├── music
│  └── tv
└── media
   ├── movies
   ├── music
   └── tv
```

### Jellyfin

```txt
/data
└── media
   ├── movies
   ├── music
   └── tv
```

## Configurations

In addition, configurations are stored at `/mnt/storage/{name of service}/config` so they can be backed up easily.

## Peertube Configuration

Peertube has been added to the streaming stack and requires the following secrets to be configured in the Ansible vault:

### Required Vault Variables

Add the following variables to `ansible/hosts/group_vars/apps/vault.yml`:

```yaml
# Peertube database credentials
vault_peertube__db_username: "peertube"
vault_peertube__db_password: "<GENERATE_RANDOM_PASSWORD>"

# Peertube application secret (generate with: openssl rand -hex 32)
vault_peertube__secret: "<GENERATE_RANDOM_HEX_STRING>"

# Peertube SMTP configuration
vault_peertube__smtp_hostname: "<YOUR_SMTP_SERVER>"
vault_peertube__smtp_port: "587"
vault_peertube__smtp_from: "noreply@<YOUR_DOMAIN>"
vault_peertube__smtp_tls: "true"
vault_peertube__smtp_disable_starttls: "false"

# Peertube admin email
vault_peertube__admin_email: "<ADMIN_EMAIL_ADDRESS>"
```

Then add the corresponding variable references to `ansible/hosts/group_vars/apps/vars.yml`:

```yaml
# Peertube configuration
peertube__db_username: "{{ vault_peertube__db_username }}"
peertube__db_password: "{{ vault_peertube__db_password }}"
peertube__secret: "{{ vault_peertube__secret }}"
peertube__smtp_hostname: "{{ vault_peertube__smtp_hostname }}"
peertube__smtp_port: "{{ vault_peertube__smtp_port }}"
peertube__smtp_from: "{{ vault_peertube__smtp_from }}"
peertube__smtp_tls: "{{ vault_peertube__smtp_tls }}"
peertube__smtp_disable_starttls: "{{ vault_peertube__smtp_disable_starttls }}"
peertube__admin_email: "{{ vault_peertube__admin_email }}"
```

### Generating Secrets

Generate the required secrets using these commands:

```bash
# Generate a random password for the database
openssl rand -base64 32

# Generate the Peertube secret
openssl rand -hex 32
```

### Peertube Data Structure

Peertube data is stored in the following locations:

```txt
{{ docker_mounts_directory }}/peertube/
├── data/       # Video files and user-uploaded content
├── config/     # Peertube application configuration
├── db/         # PostgreSQL database files
└── redis/      # Redis cache data
```

### Access

Once deployed, Peertube will be available at `https://peertube.{{ main_domain }}`. 

**IMPORTANT SECURITY NOTICE**: The first user to register will become the administrator of the instance. After deployment:
1. Immediately register your admin account
2. Disable public registration in Admin → Configuration → Signup to prevent unauthorized access

For detailed setup instructions and security considerations, see `SECRETS.md`.
