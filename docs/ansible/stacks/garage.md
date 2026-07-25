# Garage Stack

## Overview

The **Garage** stack provides S3-compatible object storage with a web UI, intended for binary caching (for example, Nix cache artifacts).

This deployment is intentionally simple:

- single node
- replication factor `1`
- S3 endpoint routed by Traefik on `s3.{{ main_domain }}`
- garage-ui routed by Traefik on `garage.{{ main_domain }}`
- garage-ui protected with `authelia@docker`

## Components

### Garage

- **Image**: `dxflrs/garage:v2.1.0`
- **Container**: `garage`
- **Role**: S3-compatible object storage backend
- **Config**: `{{ garage__config_dir }}/garage.toml`
- **Data**: `{{ garage__data_dir }}`
- **Metadata**: `{{ garage__meta_dir }}`

### Garage UI

- **Image**: `khairul169/garage-webui:1.1.0`
- **Container**: `garage-ui`
- **Role**: Bucket and key management UI
- **Access**: `https://garage.{{ main_domain }}`

## Routing

- S3 API: `https://{{ garage__s3_subdomain }}.{{ main_domain }}`
- UI: `https://{{ garage__ui_subdomain }}.{{ main_domain }}`

S3 is public internet-facing by design in this setup.

## Required Secrets

Set these vault variables before deploying:

- `vault_garage__rpc_secret`
- `vault_garage__admin_token`
- `vault_garage__metrics_token`

A simple way to generate values:

```bash
openssl rand -hex 32
```

## Deploy

```bash
just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\":[\"garage\"]}"'
```

## One-Time Bootstrap (Manual)

After first deploy, initialize the Garage layout inside the container:

```bash
# Get node ID from node public key
NODE_ID=$(docker exec garage sh -lc 'xxd -p /var/lib/garage/meta/node_key.pub | tr -d "\\n"')

# Helper function for Garage CLI
garage() {
  docker exec garage /garage -c /etc/garage.toml --rpc-host "${NODE_ID}@127.0.0.1:3901" "$@"
}

# Inspect status
garage status

# Assign 1 node with desired capacity (adjust capacity to your disk)
garage layout assign "$NODE_ID" -z dc1 -c 500G

# Apply layout
garage layout apply --version 1
```

## Nix Binary Cache Notes

For Nix binary caching, create a dedicated bucket and access key/secret in garage-ui, then point your caching workflow to:

- endpoint: `https://{{ garage__s3_subdomain }}.{{ main_domain }}`
- region: `{{ garage__s3_region }}`

Keep credentials scoped to the specific cache bucket.
