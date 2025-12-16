{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.nh;
in
{
  options.nh = {
    username = lib.mkOption { default = "snyssen"; };
    flakePath = lib.mkOption { default = "source/repos/mother-of-all-infra"; };
  };

  config = {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/${cfg.username}/${cfg.flakePath}"; # sets NH_OS_FLAKE variable for you
    };
  };
}
