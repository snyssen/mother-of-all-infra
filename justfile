alias apb := ansible-playbook
alias apl := ansible-playbook-list
alias au := ansible-update
alias ssh := ssh-connect
alias nhr := nix-remote-install
alias nbc := nix-build-cache

hostname := `hostname`

# Default recipe, list all available recipes
default:
  just --list

# Initial setup for entire repository
setup: pre-commit-setup ansible-setup ansible-vault-setup

# Setup pre-commit hooks
pre-commit-setup:
  pre-commit install

# Install Ansible Galaxy collections
[working-directory: 'ansible']
ansible-setup:
  ansible-galaxy collection install -r requirements.yml
  ansible-galaxy role install -r requirements.yml

# Update Ansible Galaxy collections
[working-directory: 'ansible']
ansible-update:
  ansible-galaxy collection install -r requirements.yml --force
  ansible-galaxy role install -r requirements.yml --force

# Setup Ansible Vault password
ansible-vault-setup:
  scripts/set-private-var.sh ANSIBLE_VAULT_PASSPHRASE

# List available Ansible playbooks
[working-directory: 'ansible']
ansible-playbook-list:
  @echo "Available Ansible Playbooks:"
  @ls playbooks/*.ansible.yml | xargs -n 1 basename | sed 's/\.ansible\.yml//' | sed 's/^/ - /'

# Run an Ansible playbook
[working-directory: 'ansible']
ansible-playbook playbook *flags:
  ansible-playbook playbooks/{{playbook}}.ansible.yml {{flags}}

# Test connectivity to a host via SSH (forcing tailscale login if necessary)
ssh-connect +hosts:
  for host in {{hosts}}; do ssh "$host" echo "connected to $host."; done

# Build NixOS configuration and push result to cache with attic
nix-build-cache host=hostname:
  nh os build -H {{host}}
  attic push snyssen-infra result

# Update NixOS configuration on a remote host using nh (requires tailscale for DNS and root SSH access)
nix-remote-install host ip=host:
  nh os switch -H {{host}} --target-host=root@{{ip}}

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

# Setup state backend (s3 on backblaze) for Terraform
terraform-state-backend-setup:
  scripts/set-private-var.sh AWS_ACCESS_KEY_ID
  scripts/set-private-var.sh AWS_SECRET_ACCESS_KEY

# Setup openstack for terraform operations on gandi.net
terraform-openstack-setup:
  scripts/set-private-var.sh OS_USERNAME
  scripts/set-private-var.sh OS_PROJECT_NAME
  scripts/set-private-var.sh OS_PASSWORD
