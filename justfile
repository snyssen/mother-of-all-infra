import "ansible/ansible.just"
import "nix/nix.just"
import "terraform/terraform.just"
import "hypervisor/hypervisor.just"

alias ssh := ssh-connect

hostname := `hostname`

# Default recipe, list all available recipes
default:
  just --list

# Initial setup for entire repository
setup: pre-commit-setup ansible-setup ansible-vault-setup

# Setup pre-commit hooks
pre-commit-setup:
  pre-commit install

# Test connectivity to a host via SSH (forcing tailscale login if necessary)
ssh-connect +hosts:
  for host in {{hosts}}; do ssh "$host" echo "connected to $host."; done

# Generate age key for current host, for use with SOPS
sops-gen-privkey privKeyPath="~/.ssh/id_ed25519" ageKeyPath="~/.config/sops/age/keys.txt":
  mkdir -p $(dirname {{ ageKeyPath }})
  ssh-to-age -private-key -i {{ privKeyPath }} > {{ ageKeyPath }}
  chmod 600 {{ ageKeyPath }}

# Get public age key of current host, for use with SOPS
sops-get-pubkey ageKeyPath="~/.config/sops/age/keys.txt":
  age-keygen -y {{ ageKeyPath }}

# Use SOPS to create or update secrets in given file
sops-update file:
  sops {{file}}

# Rotate SOPS keys for given file, based on rules from `.sops.yaml`
sops-update-keys file:
  sops updatekeys {{file}}

# Rotate SOPS keys for every secret file in the repo, based on rules from `.sops.yaml`
sops-update-keys-all *flags:
  scripts/sops-update-keys-all.sh {{flags}}

# Copy Ansible Vault secrets into a SOPS file without printing them (mappings: vault_var=sops/key/path)
sops-from-vault file +mappings:
  scripts/sops-from-vault.sh {{file}} {{mappings}}

# Store stdin as one key of a SOPS file without printing it (e.g. `ssh host cat key.pem | just sops-set-stdin <file> <key/path>`)
sops-set-stdin file key:
  scripts/sops-set-stdin.sh {{file}} {{key}}

# Generate a random secret (64 chars, or --length N), or with --oidc-client an Authelia client id/secret/hash, into a SOPS file without printing it
sops-gen-secret +args:
  scripts/sops-gen-secret.sh {{args}}

# Store a Grafana service account token for the Grafana MCP server in .mcp.json
grafana-mcp-setup:
  scripts/set-private-var.sh GRAFANA_SERVICE_ACCOUNT_TOKEN

# Run mkdocs website locally
run-docs:
  nix run .#docs
