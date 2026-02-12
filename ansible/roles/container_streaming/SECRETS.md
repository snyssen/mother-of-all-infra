# Peertube Secrets Configuration Guide

This document describes the secrets that need to be added to the Ansible vault to deploy Peertube.

## Overview

Peertube requires several secrets for:
- Database authentication (uses shared PostgreSQL database)
- Application security (secret key)
- SMTP email configuration

## Step-by-Step Setup

### 1. Generate Required Secrets

First, generate the necessary random values:

```bash
# Generate database password (32 characters)
openssl rand -base64 32

# Generate Peertube secret key (64 character hex string)
openssl rand -hex 32
```

### 2. Update Vault File

Edit the encrypted vault file:

```bash
just sops-update ansible/hosts/group_vars/apps/vault.yml
```

Add the following variables to the vault file:

```yaml
# Peertube Database Password
vault_peertube__db_password: "<PASTE_GENERATED_PASSWORD_HERE>"

# Peertube Application Secret (REQUIRED - generate with: openssl rand -hex 32)
vault_peertube__secret: "<PASTE_GENERATED_SECRET_HERE>"

# Peertube SMTP Configuration
# Replace with your actual SMTP server details
vault_peertube__smtp_hostname: "smtp.example.com"
vault_peertube__smtp_port: "587"
vault_peertube__smtp_from: "noreply@example.com"
vault_peertube__smtp_tls: "true"
vault_peertube__smtp_disable_starttls: "false"

# Peertube Admin Email
vault_peertube__admin_email: "admin@example.com"

# Authelia OIDC Configuration for Peertube
vault_backbone__authelia__oidc_peertube_clientid: "peertube"
vault_backbone__authelia__oidc_peertube_clientsecret: "<PASTE_GENERATED_OIDC_SECRET_HERE>"
vault_backbone__authelia__oidc_peertube_clientsecret_hash: "<PASTE_HASHED_OIDC_SECRET_HERE>"
```

**Generating OIDC Secrets:**
```bash
# Generate OIDC client secret
openssl rand -base64 32

# Generate hash for the secret (replace <SECRET> with the generated secret)
docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password '<SECRET>'
```

### 3. Update Variables File

Edit the non-encrypted variables file:

```bash
vim ansible/hosts/group_vars/apps/vars.yml
```

**A. Add the Peertube database to the `db__pg_databases` list:**

```yaml
db__pg_databases:
  # ... existing databases ...
  - name: peertube
    password: "{{ vault_peertube__db_password }}"
```

**B. Add these variable mappings (these reference the vault variables):**

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

# Optional: Override trust proxy networks if your Docker network uses a different subnet
# Default: ["127.0.0.1", "loopback", "172.18.0.0/16"]
# peertube__trust_proxy_networks: '["127.0.0.1", "loopback", "192.168.0.0/16"]'
```

## Secret Descriptions

### Database Credentials

- **vault_peertube__db_password**: PostgreSQL database password for the Peertube database in the shared PostgreSQL instance (generate randomly)

**Note**: Peertube uses the shared PostgreSQL database managed by the `databases` stack. The database username is hardcoded to `peertube` and matches the database name.

### Application Secret

- **vault_peertube__secret**: A random hex string used for cryptographic operations
  - **CRITICAL**: This must be kept secret and never changed after first deployment
  - Generate with: `openssl rand -hex 32`
  - Length: 64 characters (32 bytes in hex)

### SMTP Configuration

- **vault_peertube__smtp_hostname**: Your SMTP server hostname
- **vault_peertube__smtp_port**: SMTP port (typically 587 for TLS, 465 for SSL, or 25 for unencrypted)
- **vault_peertube__smtp_from**: Email address to use as sender
- **vault_peertube__smtp_tls**: Enable TLS encryption (`"true"` or `"false"`)
- **vault_peertube__smtp_disable_starttls**: Disable STARTTLS (`"true"` or `"false"`)
- **vault_peertube__admin_email**: Administrator email address

## SMTP Configuration Examples

### Using Gmail

```yaml
vault_peertube__smtp_hostname: "smtp.gmail.com"
vault_peertube__smtp_port: "587"
vault_peertube__smtp_from: "your-email@gmail.com"
vault_peertube__smtp_tls: "true"
vault_peertube__smtp_disable_starttls: "false"
```

### Using a Local Postfix Relay

```yaml
vault_peertube__smtp_hostname: "postfix"  # or IP of your mail server
vault_peertube__smtp_port: "25"
vault_peertube__smtp_from: "noreply@yourdomain.com"
vault_peertube__smtp_tls: "false"
vault_peertube__smtp_disable_starttls: "false"
```

### Using Office 365

```yaml
vault_peertube__smtp_hostname: "smtp.office365.com"
vault_peertube__smtp_port: "587"
vault_peertube__smtp_from: "your-email@yourdomain.com"
vault_peertube__smtp_tls: "true"
vault_peertube__smtp_disable_starttls: "false"
```

## Verification

After updating the vault and variables files, verify that the variables are correctly configured:

```bash
# Test that variables are accessible (will prompt for vault password)
cd ansible
ansible -i hosts/prod.yml apps -m debug -a "var=peertube__db_username"
```

## Deployment

Once secrets are configured, deploy the stacks in order:

```bash
# 1. Deploy/update the databases stack first to create the Peertube database
just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\":[\"databases\"]}"'

# 2. Deploy/update the backbone stack to add Peertube OIDC client to Authelia
just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\":[\"backbone\"]}"'

# 3. Then deploy the streaming stack with Peertube
just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\":[\"streaming\"]}"'
```

## Security Notes

1. **Never commit unencrypted secrets** to version control
2. **OIDC Authentication**: Peertube uses OpenID Connect with Authelia for authentication
3. The `vault_peertube__secret` is particularly sensitive - it's used for:
   - Session management
   - Token generation
   - Cryptographic operations
4. The OIDC client secret and its hash must match - always generate the hash from the plaintext secret
5. Changing the secret after deployment will:
   - Invalidate all existing sessions
   - Break authentication tokens
   - Potentially cause data corruption
6. Backup your vault passphrase securely
7. Use strong, randomly generated passwords

## Troubleshooting

### SMTP Issues

If email is not working:

1. Check SMTP credentials and hostname
2. Verify firewall allows outbound connections on the SMTP port
3. Check Peertube logs: `docker logs peertube`
4. Test SMTP connectivity from the host: `telnet smtp.example.com 587`

### Database Connection Issues

If Peertube cannot connect to the database:

1. Verify the database was created by the `databases` stack
2. Check that the `peertube` database exists: `docker exec -it postgres psql -U postgres -l`
3. Verify the database password matches in vault and variables
4. Check shared database logs: `docker logs postgres`
5. Ensure the databases stack is running: `docker ps | grep postgres`

### OIDC Authentication Issues

If you cannot log in via Authelia OIDC:

1. Verify the Authelia OIDC client is configured correctly
2. Check that the client secret hash matches the plaintext secret
3. Verify the redirect URI in Authelia matches: `https://peertube.yourdomain.com/plugins/auth-openid-connect/router/code-cb`
4. Check Peertube logs for OIDC errors: `docker logs peertube`
5. Check Authelia logs: `docker logs authelia`
6. Verify the discovery URL is accessible: `curl https://auth.yourdomain.com/.well-known/openid-configuration`
7. Ensure the Peertube OIDC plugin is enabled (it's configured via environment variables)

### General Authentication Issues

If you cannot access Peertube:

1. Verify Authelia is running: `docker ps | grep authelia`
2. Check Authelia logs: `docker logs authelia`
3. Ensure you're using the correct domain: `https://peertube.yourdomain.com`

### First-Time Setup

After deployment:

1. Navigate to `https://peertube.yourdomain.com` (replace with your actual domain)
2. Click "Login with Authelia" button on the Peertube login page
3. You'll be redirected to Authelia for authentication
4. After successful Authelia authentication, you'll be redirected back to Peertube
5. Your user account will be automatically created based on your Authelia identity
6. **IMPORTANT**: The first OIDC user may need to be manually promoted to administrator:
   ```bash
   # Promote user to admin via database
   docker exec -it postgres psql -U peertube -d peertube -c "UPDATE \"user\" SET role = 0 WHERE username = '<your-username>';"
   ```
7. Configure public registration settings in Admin → Configuration → Signup
8. Complete the initial setup wizard
9. Configure additional settings through the admin interface

### Performance Tuning

The default configuration uses conservative memory limits:
- Redis: 64MB (suitable for light usage)

For production instances with significant usage, consider adjusting Redis in the docker-compose.yml:
- Redis: Increase to 128-256MB for high-traffic instances

**Note**: PostgreSQL memory is managed by the shared `databases` stack, not in the streaming stack configuration.
