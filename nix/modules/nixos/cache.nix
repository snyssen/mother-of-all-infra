{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.cache;
in
{
  options.cache = { };

  config = {
    nix.settings = {
      substituters = [
        # self-hosted attic cache (priority)
        "https://attic.snyssen.be/snyssen-infra"

        # default
        "https://cache.nixos.org"

        # nix community's cache server
        "https://nix-community.cachix.org"

        # garnix
        "https://cache.garnix.io"
      ];
      trusted-public-keys = [
        # self-hosted attic cache public key
        # Retrieve with: attic cache info snyssen-infra (after deployment)
        "snyssen-infra:dxx9yngQiQbhs+XqBC0kN9tb5iU1Sqbs11Mr2EarYIs="

        # nix community's cache server public key
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

        # garnix
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
    environment.systemPackages = [
      pkgs.attic-client
    ];
  };
}
