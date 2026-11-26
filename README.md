# Snyssen's "Mother of All Infra" repository

This repository aims to group all of my personal infra config in a single place, mostly managed by [nix](https://nixos.org/).

## Structure

- `nix/` contains all nix and nixos related code: every NixOS host, including the apps server (`nix/hosts/apps-01/`) and its Docker Compose stacks. Most of it was originally imported from [nixos-config](https://github.com/snyssen/nixos-config).
- `ansible/` contains the imperative work that stays awkward in Nix: building and provisioning libvirt VM images, configuring the Technitium DNS cluster, and the bare-metal backup server. See its own [README](./ansible/README.md).
- `hypervisor/` contains `just` recipes driving libvirt on the hypervisor over SSH.
- `docs/` contains the documentation, published with mkdocs (`just run-docs` to preview it locally).
- `scripts/` contains re-usable scripts, usually called through [just](https://just.systems/) recipes.
- `terraform/` contains terraform code, usually used to create the machines onto which nixos systems are then deployed.

## Get Started

Since the repos is centered around a nix flake, it requires nix to be properly used. This means either using a full nixos system, or installing the nix package manager on your system. For the latter, I recommend using the [Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer).

You can then either use

```sh
nix develop
```

Or install [direnv](https://direnv.net/) and allow loading this directory to enter the devshell (which is defined at `nix/devshell.nix`). Once in the devshell, enter

```sh
just setup
```

To fully initialize the environment. You can list the available commands by simply running

```sh
just --list
```
