# AGENTS.md — Mother of All Infra

**This is the single source of truth for agent and contributor guidance in this repo.**
`CLAUDE.md` imports this file and `.github/copilot-instructions.md` is a symlink to it —
edit this file, never those.

Personal monorepo for self-hosted infrastructure, managed with Nix (flake), Ansible, and
Terraform. Single maintainer.

## Layout

- `nix/` — NixOS + Home Manager modules and per-host configs. Flake uses `numtide/blueprint` with `prefix = "nix/"`, so directory structure IS the flake output structure:
  - `nix/hosts/<host>/` — one dir per machine (`configuration.nix`, `hardware-configuration.nix`, `users/<user>.nix`, `data/secrets.yaml` for SOPS). Blueprint turns each into a `nixosConfigurations.<host>` (or `darwinConfigurations`) output.
  - `nix/modules/nixos/` and `nix/modules/home/` — reusable NixOS and Home Manager modules, one concern per file (e.g. `docker.nix`, `sops.nix`, `stylix.nix`).
  - `nix/hosts/apps/compose/<stack>/` — the Nix successor to the `container_*` Ansible roles: a `default.nix` plus a `docker-compose.yaml` per stack, each realised as a `compose-<stack>.service` unit.
  - `nix/devshell.nix` — the repo's dev shell.
- `ansible/` — service deployment (legacy; see the note below):
  - `playbooks/` — named `<context>-<action>.ansible.yml` (e.g. `stacks-deploy.ansible.yml`, `server-reboot.ansible.yml`).
  - `roles/` — roles prefixed `container_<name>` each deploy one Docker Compose stack (`tasks/main.yml` templates a `docker-compose.yml` and manages that stack's volumes, config and secrets).
  - `hosts/` — inventories: `dev.yml` (default), `staging` equivalent, `prod.yml`, `test.yml`, plus `group_vars`/`host_vars`.
- `terraform/` — provider IaC: `gandi/`, `ovh/` (each with `bootstrap/` + `infra/`).
- `hypervisor/` — libvirt VMs driven via `virsh` over SSH to the `hypervisor` host.
- `scripts/` — helper scripts invoked by `just` recipes and devshell hooks.
- `docs/` — mkdocs site; preview with `just run-docs`.

Why it is shaped this way: the Nix flake and `devshell.nix` give a reproducible dev
environment, and `just` keeps automation out of ad-hoc shell scripts. Terraform provisions
the cloud machines and their IAM (an OVH VPS, a Gandi OpenStack instance); Nix then
configures those hosts, alongside the bare-metal and libvirt ones.

**Ansible is legacy, but it is still what runs current production.** Service deployment is
migrating to Nix, which will configure both the hosts and the apps on them — see
`nix/hosts/apps/` and `docs/hypervisor/apps-migration-plan.md`. Ansible keeps a permanent
but narrow role for imperative work that is awkward in Nix, chiefly building and
provisioning the libvirt VM images. So treat `ansible/roles/container_*` as live-but-
legacy: authoritative for prod today, while new service work generally belongs on the Nix
side. When the two disagree, ask which one the task means.

## Dev environment

- Enter the devshell with `nix develop`, or install direnv (`.envrc` auto-loads the flake). Devshell packages: `nixfmt`, `nixd`, `just`, `pre-commit`, `ansible`, `ansible-lint`, `terraform`, `sops`, `age`, `ssh-to-age`, `openstackclient`.
- First run: `just setup` → installs pre-commit hooks, Ansible Galaxy collections/roles (`ansible/requirements.yml`), and prompts for the Ansible Vault passphrase (written to `.envrc.private`, never committed).
- List all tasks: `just --list`. The root `justfile` imports `ansible/ansible.just`, `nix/nix.just`, `terraform/terraform.just`, `hypervisor/hypervisor.just`.
- On every devshell load, `scripts/git-main-safety-check.sh warn` runs (throttled fetch) to warn if the tree is behind/dirty.
- **`just` recipes take positional arguments, not `name=value`.** `just nix-build blackfog`, not `just nix-build host=blackfog` — the latter is accepted silently and passes the literal string `host=blackfog` through. Check a signature with `just --list`, and dry-run anything you are unsure of with `just --dry-run <recipe> <args>`.

## Nix

- Build a host: `just nix-build <host>` → `nh os build -H <host>`. To apply a config to the machine you are on, `nh os switch`.
- Push to the S3 binary cache: `just nix-build-cache <host>` (or `just nix-build-cache-sign <host> [keyFile]` with a signing key).
- Remote install/switch: `just nix-remote-install <build|switch|boot|test> <host> [ip]` → `nh os <action> -H <host> --target-host=root@<ip>` (needs Tailscale DNS + root SSH). `ip` defaults to the host name.
- Validate the whole flake: `just nix-check` → `nix flake check`. CI is self-hosted **argunix** (<https://codeberg.org/tfc/argunix>, running at `argunix.snyssen.be`), which evaluates `nixosConfigurations` directly; `flake.nix` prunes `nixos-*`/`darwin-*`/`system-*` closure-duplicate checks to reduce its eval fan-out. `.github/workflows/nix.yml` only checks flake *inputs*, so Renovate has a passing status to automerge against. The CI setup is in flux — confirm against `flake.nix` and `.github/workflows/` rather than trusting this paragraph.
- `pkgs.unstable` is exposed everywhere via an overlay (defined in `flake.nix`); use it for packages that need nixpkgs-unstable.
- To add a new host: create `nix/hosts/<name>/` with `configuration.nix` + `hardware-configuration.nix` (+ `users/`, `data/secrets.yaml` if needed) — blueprint picks it up automatically, no `flake.nix` edits required.
- Test host changes with `nh os build -H <host>` before asking for a deploy.

## Ansible (read this before running anything)

- **Legacy, but it is what runs production today.** Prefer Nix for new service work. Reach for Ansible when touching the current prod apps server, or the imperative playbooks that outlive the migration (`libvirt-image-build`, `libvirt-provision`).
- Run a playbook via the task runner: `just ansible-playbook <playbook> [flags]`, e.g. `just ansible-playbook stacks-deploy -i hosts/prod.yml -e '{"stacks_deploy_list":["nextcloud"]}'`. Aliases: `just apb`, `just apl` (list playbooks), `just au` (update collections/roles).
- **Safety gate:** `just ansible-playbook` first runs `scripts/git-main-safety-check.sh enforce`, which fails unless you are on `main`, have a clean tree, and are in sync with upstream. Bypass once with `ALLOW_UNSAFE_ANSIBLE_RUN=1` (discouraged).
- The `ansible-playbook` and `ansible-setup`/`ansible-update` recipes run with `working-directory: 'ansible'`. If invoking `ansible-playbook` manually, `cd ansible/` first (or pass `-i ansible/hosts/<env>.yml` and playbook paths relative to `ansible/`).
- Inventories in `ansible/hosts/`: `dev` (default), `staging`, `prod`. Pass with `-i hosts/<env>.yml`.
- Destructive playbooks exist (`server-wipe`, `server-shutdown`, `server-reboot`): never run against prod without explicit instruction.
- Adding a new stack: create `ansible/roles/container_<name>/` with `tasks/main.yml` + `templates/docker-compose.yml`, then wire it into `stacks-deploy.ansible.yml` / `stacks-manage.ansible.yml`.

## Terraform

- State backend (Backblaze S3): `just terraform-state-backend-setup` (sets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` into `.envrc.private` via `scripts/set-private-var.sh`).
- OpenStack for Gandi: `just terraform-openstack-setup` (sets `OS_USERNAME`/`OS_PROJECT_NAME`/`OS_PASSWORD`). Gandi OpenStack vars are also exported from `.envrc`.

## Hypervisor

- `just hypervisor-*` wrap `virsh` over SSH to the `hypervisor` host: `just hypervisor-vm-list`, `just hypervisor-vm-start <vm>` (also stop/reboot/destroy/console/info), plus `just hypervisor-btrfs-scrub <pool>` and usage/stats/devices.
- Build VM disk images: `just hypervisor-build-vm-images`; provision: `just hypervisor-provision-vms` (both run ansible playbooks against `hosts/prod.yml`).

## Secrets

- SOPS (age): per-host key groups are defined in `.sops.yaml`; encrypted secrets live under `nix/hosts/<host>/data/*`. Edit with `just sops-update <file>`; rotate keys with `just sops-update-keys <file>`.
- Ansible Vault passphrase lives in `.envrc.private` (gitignored). Never print or commit it, or any SOPS/age key material.
- pre-commit hook `ansible-vault-encrypted` checks `vault.yml` stays encrypted.

## Conventions & safety

- **Git is the maintainer's.** Make the edits, leave them in the working tree, and stop there — the maintainer reviews and handles `git add` / `commit` / `push` and branch creation. Do not run git write commands unless asked to in that same message; this holds for one-line changes, and when the task was framed as "open a PR". Report what is ready to commit instead.
- Conventional commits are enforced by pre-commit (`conventional-pre-commit` on `commit-msg`), so write proposed messages in that form.
- Dependency bumps are owned by Renovate (`renovate.json5`: nix enabled, lockfile maintenance, semantic commits, grouped). Do not hand-edit version pins that Renovate manages without explicit approval. Note `minimumReleaseAge` is 3 days, so Renovate deliberately lags fresh releases — call this out when a security fix is involved.
- Treat `nix/hosts/*`, `terraform/*`, and `ansible/hosts/prod.yml` as live infrastructure: require explicit owner approval before editing or deploying.
- Never run destructive Ansible playbooks (`server-wipe`, `server-shutdown`, `server-reboot`), remote commands against production, or anything that alters live infrastructure, without explicit instruction.
- Do not make unilateral changes to live container stacks managed by `container_` roles — they own volumes and configs as well as the compose file.
- Never commit secrets, private keys or SOPS key material, and never print age keys or vault passphrases in diffs, messages or PRs.
- Do not send repository contents to external services beyond what the task plainly requires.

## Working in this repo

- Keep changes minimal, reversible and well-documented; prefer local edits that preserve the existing Nix and Ansible structure. Add a `just` recipe rather than a new ad-hoc script.
- Read `README.md`, `ansible/README.md`, `justfile` and `nix/devshell.nix` before design or tooling changes.
- Run checks inside the devshell (`nix develop`) so the environment matches: `nix flake check`, `nixfmt`, `ansible-lint`, `pre-commit run --files <paths>`.
- When a change needs privileged or network access, write out the exact commands for the maintainer to run instead of running them.
- Verify against the real files rather than this prose. This is a personal repo and docs go stale; playbooks, roles, `justfile` recipes and Nix modules are authoritative when they disagree with anything written here.
