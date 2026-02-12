# Peertube Secrets Configuration Guide

This document describes the secrets that need to be added to the Ansible vault to deploy Peertube.

## Overview

Peertube requires several secrets for:
- Database authentication
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
# Peertube Database Configuration
vault_peertube__db_username: "peertube"
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
```

### 3. Update Variables File

Edit the non-encrypted variables file:

```bash
vim ansible/hosts/group_vars/apps/vars.yml
```

Add these variable mappings (these reference the vault variables):

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

## Secret Descriptions

### Database Credentials

- **vault_peertube__db_username**: PostgreSQL database username (default: `peertube`)
- **vault_peertube__db_password**: PostgreSQL database password (generate randomly)

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

Once secrets are configured, deploy the streaming stack:

```bash
just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\":[\"streaming\"]}"'
```

## Security Notes

1. **Never commit unencrypted secrets** to version control
2. The `vault_peertube__secret` is particularly sensitive - it's used for:
   - Session management
   - Token generation
   - Cryptographic operations
3. Changing the secret after deployment will:
   - Invalidate all existing sessions
   - Break authentication tokens
   - Potentially cause data corruption
4. Backup your vault passphrase securely
5. Use strong, randomly generated passwords

## Troubleshooting

### SMTP Issues

If email is not working:

1. Check SMTP credentials and hostname
2. Verify firewall allows outbound connections on the SMTP port
3. Check Peertube logs: `docker logs peertube`
4. Test SMTP connectivity from the host: `telnet smtp.example.com 587`

### Database Connection Issues

If Peertube cannot connect to the database:

1. Verify the database password matches in both services
2. Check database logs: `docker logs peertube_postgres`
3. Ensure the database container is running: `docker ps | grep peertube`

### First-Time Setup

After deployment:

1. Navigate to `https://peertube.{{ main_domain }}`
2. The first registered user will become the administrator
3. Complete the initial setup wizard
4. Configure additional settings through the admin interface
