{ lib, pkgs, ... }:
{
  dconf = {
    enable = true;
    settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        caffeine.extensionUuid
        pop-shell.extensionUuid
        dash-to-dock.extensionUuid
        gsconnect.extensionUuid
      ];
    };
    settings."org/gnome/desktop/interface".enable-hot-corners = false;
    settings."org/gnome/desktop/wm/preferences".resize-with-right-button = true;
    settings."org/gnome/desktop/screensaver".lock-delay = lib.hm.gvariant.mkUint32 300;
    settings."org/gnome/desktop/session".idle-delay = lib.hm.gvariant.mkUint32 600;
    settings."org/gnome/shell/extensions/pop-shell".tile-by-default = true;
  };
}
