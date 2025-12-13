alias apb := ansible-playbook
alias apl := ansible-playbook-list
alias au := ansible-update
alias ssh := ssh-connect

default:
  just --list

# Initial setup for entire repository
setup: pre-commit-setup ansible-setup ansible-vault-setup

# Setup pre-commit hooks
pre-commit-setup:
  pre-commit install

# Install Ansible Galaxy collections
ansible-setup:
  ansible-galaxy collection install -r ansible/requirements.yml

# Update Ansible Galaxy collections
ansible-update:
  ansible-galaxy collection install -r ansible/requirements.yml --force

# Setup Ansible Vault password
ansible-vault-setup:
  bash scripts/ansible-vault-setup.sh

# List available Ansible playbooks
ansible-playbook-list:
  @echo "Available Ansible Playbooks:"
  @ls ansible/playbooks/*.ansible.yml | xargs -n 1 basename | sed 's/\.ansible\.yml//' | sed 's/^/ - /'

# Run an Ansible playbook
ansible-playbook playbook *flags:
  @# Run in subshell to change directory and load ansible.cfg
  (cd ansible && ansible-playbook playbooks/{{playbook}}.ansible.yml {{flags}})

# Test connectivity to a host via SSH (forcing tailscale login if necessary)
ssh-connect +hosts:
  for host in {{hosts}}; do ssh "$host" echo "connected to $host."; done
