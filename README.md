# Snyssen's "Mother of All Infra" repository

This repository aims to group all of my personal infra config in a single place, mostly managed by [nix](https://nixos.org/).

## Structure

- `ansible/` contains my ansible code, imported from the [infra-snyssen.be](https://github.com/snyssen/infra-snyssen.be). You can also check its own [README](./ansible/README.md).
- `docs/` contains documentation. It is sadly mostly empty as I hate writing documentation... Hopefully the code itself should mostly be self-documenting.
- `nix/` contains all nix and nixos related code. It mostly serves as a nixos configuration repos, with most of its code being imported from [nixos-config](https://github.com/snyssen/nixos-config).
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
