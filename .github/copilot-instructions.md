<!-- Copied/created for GitHub Copilot-style agents -->
# Quick agent guide — Mother of All Infra

Purpose: help an AI coding agent become productive quickly in this monorepo by describing the project's architecture, developer workflows, conventions, and concrete examples.

- **Big picture**
  - This is a personal monorepo for self-hosted infrastructure managed primarily with Nix, Ansible and Terraform.
  - High level responsibilities:
    - `nix/` — Nix flakes, devshell and NixOS/Home Manager modules (system and user configuration). Hosts (desktop or headless) are defined under `nix/hosts/` and are built/deployed with `nh` (see `nh os switch` and `just nix-remote-install` examples below).
    - `ansible/` — provision/deploy/playbooks; inventories live in `ansible/hosts/` and playbooks in `ansible/playbooks/`.
    - `terraform/` — provider-specific IaC (e.g., `gandi/`, `ovh/`).
    - `scripts/` and `justfile` — developer helpers and task runner shortcuts.

- **Why things are structured this way**
  - Nix flakes and `devshell.nix` provide a reproducible dev environment. `just` is used for small automation tasks to avoid ad-hoc shell scripts.
  - Ansible manages service deployment and runtime orchestration; Terraform provisions cloud resources that Nix/Ansible use afterwards.

- **Developer workflows (concrete)**
  - Enter the devshell: run `nix develop` (or install `direnv` and load from root directory).
  - Initialize workspace: `just setup` — installs pre-commit hooks, ansible collections/roles and creates the vault passphrase helper.
  - List helper commands: `just --list`.
  - Ansible: playbooks live under `ansible/playbooks/*.ansible.yml`. Use `just ansible-playbook playbook=<name> flags='-i hosts/prod.yml -e "{...}"'` or run `ansible-playbook ansible/playbooks/<playbook>.ansible.yml -i ansible/hosts/<env>.yml`.
  - Terraform: provider dirs under `terraform/`; secrets for backends are set via `just terraform-state-backend-setup`.
  - Host builds & deploys: Nix is used to manage full hosts in `nix/hosts/`. Use `nh` to build/switch a host's system (for example `nh os switch` on the current machine). For remote installs there's a `just` helper: `just nix-remote-install <host>` (e.g. `just nix-remote-install ingress`).

- **Project-specific conventions & patterns**
  - Ansible playbooks use the naming pattern `context-action.ansible.yml` and are executed against inventories in `ansible/hosts/` (dev, staging, prod).
  - `justfile` uses `working-directory:` to change into `ansible/` for playbook-related recipes — call via `just` helpers when possible.
  - Nix flake uses `blueprint` and overlays; unstable packages are available as `pkgs.unstable` (see `flake.nix`).
  - Application stacks: roles prefixed with `container_` define software stacks deployed to application hosts. Those roles typically deploy a `docker-compose.yml` for the stack and use docker compose to manage lifecycle. The role is responsible for creating configuration files, managing volumes and wiring environment variables/secrets for the stack.

- **Integration points & external deps**
  - SOPS (age) for secrets; use `just sops-update` to edit SOPS-encrypted files.
  - Ansible Galaxy collections and roles are declared in `ansible/requirements.yml` and installed by `just ansible-setup`.
  - Nix inputs (home-manager, sops-nix, vscode extensions) are declared in `flake.nix`.
  - Services (Nextcloud, restic, snapraid, etc.) are referenced across `ansible/playbooks` and roles under `ansible/roles/`.

- **When making code changes**
  - Prefer minimal, local changes that preserve Nix and Ansible structure; update `justfile` recipes if adding new developer tasks.

- **AI agent guidance (do / always / never)**
  - **Can do:**
    - Read and explore the repository, search for relevant files, and summarize findings.
    - Propose and create non-destructive code changes (docs, tests, small helpers, refactors) and open PR drafts with clear descriptions.
    - Edit and add Nix modules, Ansible playbooks and `just` helpers locally, but prefer suggesting patches/PRs rather than pushing changes that affect live systems.
    - Run reproducible local checks inside the devshell (`nix develop`) such as formatting, linting, and unit tests; use `just` helpers for repo tasks.
    - Generate concrete examples and commands for humans to run when the change requires privileged or network access.

  - **Should always do:**
    - Use the repo `todo` process: plan work before editing, and track progress via the todo list tool.
    - Read `README.md`, `ansible/README.md`, `justfile`, and `nix/devshell.nix` before making design or tooling changes.
    - Keep changes minimal, reversible, and well-documented. Create small commits with clear messages and open PRs for review.
    - Never expose secrets or SOPS private keys. Do not print age keys or vault passphrases in PRs, diffs or messages.
    - Ask for explicit human confirmation before modifying `nix/hosts/*`, `terraform/*`, or `ansible/hosts/prod.yml` — these control live infrastructure.
    - Use `just` helpers and devshell (`nix develop`) for running repo commands to ensure environment parity.

  - **Must never do:**
    - Commit secrets, private keys, or SOPS key material to the repository.
    - Push changes that alter production infrastructure (`nix/hosts/*`, `terraform/*`, `ansible/hosts/prod.yml`) without explicit owner approval.
    - Execute destructive playbooks (e.g., `server-wipe`, `server-shutdown`, `server-reboot`) or run remote commands on production machines without explicit instructions and safety limits.
    - Exfiltrate repository content or sensitive data to external services.
    - Make unilateral changes to live container stacks managed by `container_` roles without coordination; these roles deploy `docker-compose.yml` and manage volumes/configs.

  - **Safe-edit checklist (quick):**
    - Prefer creating a branch and PR; include testing steps and `just` commands to reproduce.
    - For host-related changes: edit `nix/hosts/<host>/`, test with `nh os build -H <host>` or `nh os switch` locally, and request human review before deploying.


- **Concrete examples to cite in PRs or commits**
  - Running a playbook: `just ansible-playbook playbook=stacks-deploy flags='-i hosts/prod.yml -e "{\"stacks_deploy_list\"=[\"nextcloud\"]}"'`
  - Build/switch the current machine with `nh` (example):

```sh
nh os switch
```

  - Remote Nix install helper (example):

```sh
just nix-remote-install ingress
```

  - Add or change a host definition: edit `nix/hosts/<host>/` and test via `nh os build -H <host>`.

- **Notes & caveats**
  - This is a single-maintainer, personal repository; some docs may be stale — prefer looking at the actual files (playbooks, roles, Nix modules) over prose when uncertain.
  - Be conservative with changes to deployment tooling (Ansible/Terraform/Nix) — they control live systems.
