# Snyssen's Nix Development Environment template

This repository is a template for starting new projects with dev environment and dependencies handled by [Nix](https://nixos.org/), automatically loaded with [direnv](https://direnv.net/), and using [Just](https://github.com/casey/just) for easy initial setup and commands handling, as well as [Pre-commit](https://pre-commit.com/) for running checks on each commit.

## Pre-Requisites

This template tries to make as few assumptions about your system as possible by making sure that most dependencies are defined in the Nix flake itself. However, it still cannot avoid these two assumptions:

1. Your system can run Nix flakes.
2. Your system has direnv installed (because it is used to automatically load the flake, so it has to already be available).

For Nix flakes support, I recommend using [The Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) to install the Nix package manager on your machine. Or, for a more drastic and permanent solution, why not have your whole system be a Nix flake by [using NixOS](https://nixos.org/manual/nixos/stable/) as your operating system?

For direnv, see their [Getting Started](https://direnv.net/#getting-started) for installation instructions.

### Additional Recommendations

If you are using Visual Studio Code, I recommend installing the [direnv extension](https://marketplace.visualstudio.com/items?itemName=mkhl.direnv) as well. This way, any other extension you have installed will benefit from the dependencies added by the Nix flake.

## First Start

You have two options to start using this template:

1. If creating a new repository on Github, you can [directly use this template as its starting point](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template).
2. Otherwise, simply copy and paste the files from this repository at the root of your project.

Once the files are in place, you should:

1. Run `direnv allow` to allow direnv to load the .envrc file. This should in turn automatically build the Nix flake and load the dependencies.

You are now ready to start hacking!
