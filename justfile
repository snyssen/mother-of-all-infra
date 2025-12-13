alias apb := ansible-playbook
alias au := ansible-update

default:
  just --list

setup: pre-commit-setup ansible-setup ansible-vault-setup

pre-commit-setup:
  pre-commit install

ansible-setup:
  ansible-galaxy collection install -r ansible/requirements.yml

ansible-update:
  ansible-galaxy collection install -r ansible/requirements.yml --force

ansible-vault-setup:
  bash scripts/ansible-vault-setup.sh

ansible-playbook playbook *flags:
  # Run in subshell to change directory and load ansible.cfg
  (cd ansible && ansible-playbook playbooks/{{playbook}}.ansible.yml {{flags}})
