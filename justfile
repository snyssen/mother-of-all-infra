import "ansible/ansible.just"
import "nix/nix.just"
import "terraform/terraform.just"

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
sops-gen-privkey privKeyPath="~/.ssh/id_ed25519":
  mkdir -p ~/.config/sops/age
  ssh-to-age -private-key -i {{ privKeyPath }} > ~/.config/sops/age/keys.txt

# Get public age key of current host, for use with SOPS
sops-get-pubkey:
  age-keygen -y ~/.config/sops/age/keys.txt

# Use SOPS to create or update secrets in given file
sops-update file:
  sops {{file}}

# Rotate SOPS keys for given file, based on rules from `.sops.yaml`
sops-update-keys file:
  sops updatekeys {{file}}
