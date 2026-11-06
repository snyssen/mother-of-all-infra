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

    # Nautilus replaces Cosmic Files, which still has a few bugs, in particular when extracting
    # archives or connecting to network storage. cosmic-files itself stays installed: the NixOS
    # module lists it as a core package and cosmic-session spawns its `cosmic-files-applet`.
    # So we only hide it from the launcher and take its default handlers and file picker.
    xdg.mime.defaultApplications = {
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "inode/mount-point" = "org.gnome.Nautilus.desktop";
    };
    # Use the GTK file chooser instead of the Cosmic Files based one. This file replaces
    # xdg-desktop-portal-cosmic's own cosmic-portals.conf, so its other entries are repeated.
    xdg.portal.config.cosmic = {
      default = [
        "cosmic"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Secret" = [
        "oo7-portal"
        "gnome-keyring"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };

    environment.systemPackages = with pkgs; [
      cosmic-ext-applet-caffeine
      cosmic-ext-applet-privacy-indicator

      nautilus
      (lib.hiPrio (
        runCommand "cosmic-files-hidden" { } ''
          install -Dm644 ${cosmic-files}/share/applications/com.system76.CosmicFiles.desktop -t $out/share/applications
          sed -i -e '/^MimeType=/d' -e '/^\[Desktop Entry\]/a NoDisplay=true' $out/share/applications/com.system76.CosmicFiles.desktop
        ''
      ))

      # Screen recording
      gst_all_1.gstreamer # dependency
      obs-studio
    ];
  };
}
