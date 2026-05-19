alias apb := ansible-playbook
alias apl := ansible-playbook-list
alias au := ansible-update

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
  @bash ../scripts/git-main-safety-check.sh enforce
  ansible-playbook playbooks/{{playbook}}.ansible.yml {{flags}}
