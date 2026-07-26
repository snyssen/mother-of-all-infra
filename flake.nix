{
  description = "A monorepo containing all of snyssen's infra";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";

    firefox-addons.url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
    firefox-addons.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # Use raw scheme files directly to avoid eval-time package realization.
    tinted-schemes = {
      url = "github:tinted-theming/schemes";
      flake = false;
    };

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixcord.url = "github:FlameFlag/nixcord";
    nixcord.inputs.nixpkgs.follows = "nixpkgs";

    argunix.url = "git+https://codeberg.org/tfc/argunix";
    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Load the blueprint
  outputs =
    inputs:
    let
      flakeOutputs = inputs.blueprint {
        inherit inputs;
        prefix = "nix/";
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          inputs.nix-vscode-extensions.overlays.default
          inputs.argunix.overlays.default
          (final: _: {
            # this allows you to access `pkgs.unstable` anywhere in your config
            unstable = import inputs.nixpkgs-unstable {
              inherit (final.stdenv.hostPlatform) system;
              inherit (final) config;
            };
          })
        ];
      };

      # Argunix already evaluates `nixosConfigurations` directly.
      # Dropping host-closure duplicates from `checks` reduces CI eval fan-out.
      pruneHostClosureChecks =
        checksForSystem:
        let
          namesToDrop = builtins.filter (name: builtins.match "^(nixos|darwin|system)-.*" name != null) (
            builtins.attrNames checksForSystem
          );
        in
        builtins.removeAttrs checksForSystem namesToDrop;
    in
    flakeOutputs
    // {
      checks = builtins.mapAttrs (_: pruneHostClosureChecks) flakeOutputs.checks;
    };
}
