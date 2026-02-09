{
  lib,
  config,
  inputs,
  outputs,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.user;
in
{
  options.user = {
    username = lib.mkOption {
      default = "snyssen";
    };
  };

  config = {
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      initialPassword = "123456789";
    };
  };
}
