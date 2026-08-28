# AGENTS.md — Mother of All Infra

Personal monorepo for self-hosted infrastructure, managed with Nix (flake), Ansible, and Terraform. Single maintainer. Layout:

- `nix/` — NixOS + Home Manager modules and per-host configs (`nix/hosts/<host>/`), devshell (`nix/devshell.nix`). Flake uses `numtide/blueprint` with `prefix = "nix/"`.
- `ansible/` — service deployment: `playbooks/` (named `<context>-<action>.ansible.yml`), `roles/` (roles prefixed `container_` deploy a `docker-compose.yml` stack), `hosts/` inventories.
- `terraform/` — provider IaC: `gandi/`, `ovh/` (each with `bootstrap/` + `infra/`).
- `hypervisor/` — libvirt VMs driven via `virsh` over SSH.
- `scripts/`, `docs/` (mkdocs; preview with `just run-docs`).

## Dev environment

- Enter the devshell with `nix develop`, or install direnv (`.envrc` auto-loads the flake). Devshell packages: `nixfmt`, `nixd`, `just`, `pre-commit`, `ansible`, `ansible-lint`, `terraform`, `sops`, `age`, `ssh-to-age`, `openstackclient`.
- First run: `just setup` → installs pre-commit hooks, Ansible Galaxy collections/roles (`ansible/requirements.yml`), and prompts for the Ansible Vault passphrase (written to `.envrc.private`, never committed).
- List all tasks: `just --list`. The root `justfile` imports `ansible/ansible.just`, `nix/nix.just`, `terraform/terraform.just`, `hypervisor/hypervisor.just`.

## Nix

- Build a host: `just nix-build host=<host>` → `nh os build -H <host>`.
- Push to the S3 binary cache: `just nix-build-cache host=<host>` (optionally `just nix-build-cache-sign` with a signing key).
- Remote install/switch: `just nix-remote-install action=<build|switch|boot|test> host=<host> ip=<ip>` → `nh os <action> -H <host> --target-host=root@<ip>` (needs Tailscale DNS + root SSH).
- Validate the whole flake: `just nix-check` → `nix flake check`. Garnix CI builds every `nixosConfigurations.*` and `darwinConfigurations.*`.
- `pkgs.unstable` is exposed everywhere via an overlay.

## Ansible (read this before running anything)

- Run a playbook via the task runner: `just ansible-playbook playbook=<name> flags='-i hosts/prod.yml -e "{...}"'`. Aliases: `just apb`, `just apl` (list), `just au` (update collections).
- **Safety gate:** `just ansible-playbook` first runs `scripts/git-main-safety-check.sh enforce`, which fails unless you are on `main`, have a clean tree, and are in sync with upstream. Bypass once with `ALLOW_UNSAFE_ANSIBLE_RUN=1` (discouraged). The check also runs in `warn` mode on every devshell load (throttled fetch).
- Many ansible recipes set `working-directory: 'ansible'`, so they `cd` into `ansible/`. If you invoke `ansible-playbook` manually, run it from inside `ansible/`.
- Inventories in `ansible/hosts/`: `dev` (default), `staging`, `prod`. Pass with `-i hosts/<env>.yml`.
- Destructive playbooks exist (`server-wipe`, `server-shutdown`, `server-reboot`): never run against prod without explicit instruction.

## Terraform

- State backend (Backblaze S3): `just terraform-state-backend-setup` (sets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` into `.envrc.private` via `scripts/set-private-var.sh`).
- OpenStack for Gandi: `just terraform-openstack-setup` (sets `OS_USERNAME`/`OS_PROJECT_NAME`/`OS_PASSWORD`). Gandi OpenStack vars are also exported from `.envrc`.

## Hypervisor

- `just hypervisor-*` wrap `virsh` over SSH to the `hypervisor` host (list/start/stop/reboot/destroy/console, plus `btrfs` scrub/usage/stats).
- Build VM disk images: `just hypervisor-build-vm-images`; provision: `just hypervisor-provision-vms` (both run ansible playbooks against `hosts/prod.yml`).

## Secrets

- SOPS (age): per-host key groups are defined in `.sops.yaml`; encrypted secrets live under `nix/hosts/<host>/data/*`. Edit with `just sops-update file=<path>`; rotate keys with `just sops-update-keys file=<path>`.
- Ansible Vault passphrase lives in `.envrc.private` (gitignored). Never print or commit it, or any SOPS/age key material.
- pre-commit hook `ansible-vault-encrypted` checks `vault.yml` stays encrypted.

## Conventions & safety

- Conventional commits are enforced by pre-commit (`conventional-pre-commit` on `commit-msg`).
- Dependency bumps are owned by Renovate (`renovate.json5`: nix enabled, lockfile maintenance, semantic commits, grouped). Do not hand-edit version pins that Renovate manages.
- Treat `nix/hosts/*`, `terraform/*`, and `ansible/hosts/prod.yml` as live infrastructure: require explicit owner approval before editing or deploying. Prefer branches + PRs for review.
- Fuller agent guidance lives in `.github/copilot-instructions.md` — consult it for detailed do/never rules and PR examples.
