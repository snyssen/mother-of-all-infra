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
    environment = {
      sessionVariables = {
        NH_FLAKE = "/home/${cfg.username}/${cfg.flakePath}";
      };
      systemPackages = [ pkgs.nh ];
    };
  };
}
