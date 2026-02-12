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

### Database Configuration

Peertube uses the shared PostgreSQL database. Add the Peertube database to the `db__pg_databases` list in `ansible/hosts/group_vars/apps/vars.yml`:

```yaml
db__pg_databases:
  # ... existing databases ...
  - name: peertube
    password: "{{ vault_peertube__db_password }}"
```

### Required Vault Variables

Add the following variables to `ansible/hosts/group_vars/apps/vault.yml`:

```yaml
# Peertube database password
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

# Authelia OIDC client credentials for Peertube
vault_backbone__authelia__oidc_peertube_clientid: "peertube"
vault_backbone__authelia__oidc_peertube_clientsecret: "<GENERATE_RANDOM_SECRET>"
vault_backbone__authelia__oidc_peertube_clientsecret_hash: "<HASHED_SECRET>"
```

**Note**: Generate the OIDC client secret and its hash using:
```bash
# Generate client secret
openssl rand -base64 32

# Generate hash (using docker authelia command)
docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password '<CLIENT_SECRET>'
```

Then add the corresponding variable references to `ansible/hosts/group_vars/apps/vars.yml`:

```yaml
# Peertube configuration
peertube__db_username: "peertube"
peertube__db_password: "{{ vault_peertube__db_password }}"
peertube__secret: "{{ vault_peertube__secret }}"
peertube__smtp_hostname: "{{ vault_peertube__smtp_hostname }}"
peertube__smtp_port: "{{ vault_peertube__smtp_port }}"
peertube__smtp_from: "{{ vault_peertube__smtp_from }}"
peertube__smtp_tls: "{{ vault_peertube__smtp_tls }}"
peertube__smtp_disable_starttls: "{{ vault_peertube__smtp_disable_starttls }}"
peertube__admin_email: "{{ vault_peertube__admin_email }}"
peertube__oidc_client_id: "{{ backbone__authelia__oidc_peertube_clientid }}"
peertube__oidc_client_secret: "{{ backbone__authelia__oidc_peertube_clientsecret }}"

# Authelia OIDC configuration for Peertube
backbone__authelia__oidc_peertube_clientid: "{{ vault_backbone__authelia__oidc_peertube_clientid }}"
backbone__authelia__oidc_peertube_clientsecret: "{{ vault_backbone__authelia__oidc_peertube_clientsecret }}"
backbone__authelia__oidc_peertube_clientsecret_hash: "{{ vault_backbone__authelia__oidc_peertube_clientsecret_hash }}"

# Optional: Trust proxy networks (default: ["127.0.0.1", "loopback", "172.18.0.0/16"])
# Only override if your Docker network uses a different subnet
# peertube__trust_proxy_networks: '["127.0.0.1", "loopback", "192.168.0.0/16"]'
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
└── redis/      # Redis cache data
```

Note: Database files are stored in the shared PostgreSQL container managed by the `databases` stack.

### Authentication

Peertube is configured to use OpenID Connect (OIDC) authentication with Authelia. The `peertube-plugin-auth-openid-connect` plugin is automatically configured via environment variables.

**Authentication Flow:**
1. Users click "Login with Authelia" on the Peertube login page
2. They are redirected to Authelia for authentication
3. After successful authentication, users are returned to Peertube
4. User accounts are automatically created in Peertube based on OIDC claims

**Important**: The first user to log in via OIDC may need to be manually promoted to admin status through the Peertube database or CLI.

### Access

Once deployed, Peertube will be available at `https://peertube.{{ main_domain }}`. 

**OIDC Authentication Setup:**
1. Navigate to `https://peertube.{{ main_domain }}`
2. Click "Login with Authelia" button
3. Authenticate through Authelia
4. Your user account will be automatically created in Peertube
5. The first user may need to be promoted to admin (see below)

**Promoting First User to Admin:**
```bash
# Connect to Peertube container
docker exec -it peertube npm run reset-password -- -u <username>

# Or promote to admin via database
docker exec -it postgres psql -U peertube -d peertube -c "UPDATE \"user\" SET role = 0 WHERE username = '<username>';"
```

**Security Notes:**
- Public registration can be disabled in Admin → Configuration → Signup
- OIDC users are authenticated through Authelia, providing SSO across your infrastructure

For detailed setup instructions and security considerations, see `SECRETS.md`.
