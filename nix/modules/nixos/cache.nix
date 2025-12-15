{ lib, config, ... }:
let
  cfg = config.cache;
in
{
  options.cache = { };

  config = {
    nix.settings = {
      substituters = [
        # default
        "https://cache.nixos.org"

        # nix community's cache server
        "https://nix-community.cachix.org"

        # garnix
        "https://cache.garnix.io"
      ];
      trusted-public-keys = [
        # nix community's cache server public key
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="

        # garnix
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
  };
}
