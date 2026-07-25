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
  options.cache = {
    cache_snyssen_be = {
      enable = lib.mkEnableOption "the self-hosted S3 binary cache on snyssen.be" // {
        default = true;
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://cache.snyssen.be";
        description = "The URL of the S3 binary cache hosted on snyssen.be.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "cache.snyssen.be:YbGmg46EztCHAFVaMztDfW/tuSuqVjLlYeG67R3VhGY=";
        description = "The public key of the S3 binary cache hosted on snyssen.be.";
      };
    };
    attic = {
      enable = lib.mkEnableOption "the self-hosted attic cache";
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://attic.snyssen.be/snyssen-infra";
        description = "The URL of the self-hosted attic cache.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "snyssen-infra:dxx9yngQiQbhs+XqBC0kN9tb5iU1Sqbs11Mr2EarYIs=";
        description = "The public key of the self-hosted attic cache.";
      };
    };
    cachix = {
      enable = lib.mkEnableOption "the nix-community cachix cache (https://nix-community.cachix.org)" // {
        default = true;
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://nix-community.cachix.org";
        description = "The URL of the nix-community cachix cache.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
        description = "The public key of the nix-community cachix cache.";
      };
    };
    garnix = {
      enable = lib.mkEnableOption "the garnix cache (https://cache.garnix.io)" // {
        default = true;
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "https://cache.garnix.io";
        description = "The URL of the garnix cache.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=";
        description = "The public key of the garnix cache.";
      };
    };
  };

  config = {
    nix.settings = {
      substituters =
        [ ]
        ++ lib.lists.optional cfg.attic.enable cfg.attic.url
        ++ lib.lists.optional cfg.cache_snyssen_be.enable cfg.cache_snyssen_be.url
        ++ lib.lists.optional cfg.cachix.enable cfg.cachix.url
        ++ lib.lists.optional cfg.garnix.enable cfg.garnix.url;
      trusted-public-keys =
        [ ]
        ++ lib.lists.optional cfg.attic.enable cfg.attic.publicKey
        ++ lib.lists.optional cfg.cache_snyssen_be.enable cfg.cache_snyssen_be.publicKey
        ++ lib.lists.optional cfg.cachix.enable cfg.cachix.publicKey
        ++ lib.lists.optional cfg.garnix.enable cfg.garnix.publicKey;
    };
    environment.systemPackages = if cfg.attic.enable then [ pkgs.attic-client ] else [ ];
  };
}
