alias apb := ansible-playbook
alias apl := ansible-playbook-list
alias au := ansible-update
alias ssh := ssh-connect
alias nhr := nix-remote-install

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
  bash scripts/ansible-vault-setup.sh

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

# Update NixOS configuration on a remote host using nh (requires tailscale for DNS and root SSH access)
nix-remote-install host:
  nh os switch -H {{host}} --target-host=root@{{host}}
