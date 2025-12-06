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
    zsh.enable = lib.mkEnableOption "zsh shell for user";
  };

  config = {
    programs.zsh.enable = cfg.zsh.enable;
    users.users.${cfg.username} = {
      isNormalUser = true;
      shell = lib.mkIf cfg.zsh.enable pkgs.zsh;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      initialPassword = "123456789";
    };
  };
}
