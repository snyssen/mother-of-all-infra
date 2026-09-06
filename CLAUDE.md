# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal monorepo for self-hosted infrastructure, managed with Nix (flake), Ansible, and Terraform. Single maintainer.

## Layout

- `nix/` — NixOS + Home Manager modules and per-host configs. Flake uses `numtide/blueprint` with `prefix = "nix/"`, so directory structure IS the flake output structure:
  - `nix/hosts/<host>/` — one dir per machine (`configuration.nix`, `hardware-configuration.nix`, `users/<user>.nix`, `data/secrets.yaml` for SOPS). Blueprint turns each into a `nixosConfigurations.<host>` (or `darwinConfigurations`) output.
  - `nix/modules/nixos/` and `nix/modules/home/` — reusable NixOS modules and Home Manager modules, one concern per file (e.g. `docker.nix`, `sops.nix`, `stylix.nix`).
  - `nix/devshell.nix` — the repo's dev shell.
- `ansible/` — service deployment:
  - `playbooks/` — named `<context>-<action>.ansible.yml` (e.g. `stacks-deploy.ansible.yml`, `server-reboot.ansible.yml`).
  - `roles/` — roles prefixed `container_<name>` each deploy one Docker Compose stack (`tasks/main.yml` templates a `docker-compose.yml`, manages volumes/config/secrets for that stack).
  - `hosts/` — inventories: `dev.yml` (default), `staging` equivalent, `prod.yml`, `test.yml`, plus `group_vars`/`host_vars`.
- `terraform/` — provider IaC: `gandi/`, `ovh/` (each with `bootstrap/` + `infra/`).
- `hypervisor/` — libvirt VMs driven via `virsh` over SSH to the `hypervisor` host.
- `scripts/` — helper scripts invoked by `just` recipes and devshell hooks.
- `docs/` — mkdocs site; preview with `just run-docs`.

## Dev environment

- Enter the devshell with `nix develop`, or install direnv (`.envrc` auto-loads the flake). Devshell packages: `nixfmt`, `nixd`, `just`, `pre-commit`, `ansible`, `ansible-lint`, `terraform`, `sops`, `age`, `ssh-to-age`, `openstackclient`.
- First run: `just setup` → installs pre-commit hooks, Ansible Galaxy collections/roles (`ansible/requirements.yml`), and prompts for the Ansible Vault passphrase (written to `.envrc.private`, never committed).
- List all tasks: `just --list`. The root `justfile` imports `ansible/ansible.just`, `nix/nix.just`, `terraform/terraform.just`, `hypervisor/hypervisor.just`.
- On every devshell load, `scripts/git-main-safety-check.sh warn` runs (throttled fetch) to warn if the tree is behind/dirty.

## Nix

- Build a host: `just nix-build host=<host>` → `nh os build -H <host>`.
- Push to the S3 binary cache: `just nix-build-cache host=<host>` (optionally `just nix-build-cache-sign` with a signing key).
- Remote install/switch: `just nix-remote-install action=<build|switch|boot|test> host=<host> ip=<ip>` → `nh os <action> -H <host> --target-host=root@<ip>` (needs Tailscale DNS + root SSH).
- Validate the whole flake: `just nix-check` → `nix flake check`. Garnix CI builds every `nixosConfigurations.*` and `darwinConfigurations.*` (see `garnix.yaml`); `flake.nix` prunes `nixos-*`/`darwin-*`/`system-*` closure-duplicate checks to reduce CI eval fan-out.
- `pkgs.unstable` is exposed everywhere via an overlay (defined in `flake.nix`); use it for packages that need nixpkgs-unstable.
- To add a new host: create `nix/hosts/<name>/` with `configuration.nix` + `hardware-configuration.nix` (+ `users/`, `data/secrets.yaml` if needed) — blueprint picks it up automatically, no flake.nix edits required.

## Ansible (read this before running anything)

- Run a playbook via the task runner: `just ansible-playbook playbook=<name> flags='-i hosts/prod.yml -e "{...}"'`. Aliases: `just apb`, `just apl` (list playbooks), `just au` (update collections/roles).
- **Safety gate:** `just ansible-playbook` first runs `scripts/git-main-safety-check.sh enforce`, which fails unless you are on `main`, have a clean tree, and are in sync with upstream. Bypass once with `ALLOW_UNSAFE_ANSIBLE_RUN=1` (discouraged).
- The `ansible-playbook` and `ansible-setup`/`ansible-update` just recipes run with `working-directory: 'ansible'`. If invoking `ansible-playbook` manually, `cd ansible/` first (or pass `-i ansible/hosts/<env>.yml` and playbook paths relative to `ansible/`).
- Inventories in `ansible/hosts/`: `dev` (default), `staging`, `prod`. Pass with `-i hosts/<env>.yml`.
- Destructive playbooks exist (`server-wipe`, `server-shutdown`, `server-reboot`): never run against prod without explicit instruction.
- Adding a new stack: create `ansible/roles/container_<name>/` with `tasks/main.yml` + `templates/docker-compose.yml`, then wire it into `stacks-deploy.ansible.yml` / `stacks-manage.ansible.yml`.

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
- Never run destructive Ansible playbooks (`server-wipe`, `server-shutdown`, `server-reboot`) or push infra changes without explicit instruction.
- Fuller agent guidance lives in `AGENTS.md` and `.github/copilot-instructions.md` — consult them for detailed do/never rules and PR examples.
