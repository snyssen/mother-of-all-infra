{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.cosmic;
in
{
  options.cosmic = {
    enable = lib.mkEnableOption "Cosmic DE";
    autoLogin = {
      enable = lib.mkEnableOption "autoLogin feature";
      user = lib.mkOption { default = "snyssen"; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.displayManager.cosmic-greeter.enable = true;
    services.desktopManager.cosmic.enable = true;

    services.displayManager.autoLogin = lib.mkIf cfg.autoLogin.enable {
      enable = cfg.autoLogin.enable;
      user = cfg.autoLogin.user;
    };

    services.system76-scheduler.enable = true;
    programs.kdeconnect = {
      enable = true;
      package = pkgs.valent;
    };

    environment.systemPackages = with pkgs; [
      cosmic-ext-applet-caffeine
    ];
  };
}
