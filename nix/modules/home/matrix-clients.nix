{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.matrix.clients;
in
{
  options.matrix.clients = {
    element.enable = lib.mkEnableOption "Element Desktop";
    # TODO: cinny pkg is marked as broken; install as flatpak ?
    cinny.enable = lib.mkEnableOption "Cinny Desktop";
    fluffychat.enable = lib.mkEnableOption "FluffyChat";
    # TODO: commet -> only available as flatpak :(
    # TODO: Polycule? -> flatpak
  };

  config = {
    programs.element-desktop.enable = cfg.element.enable;

    home.packages =
      with pkgs;
      [ ]
      ++ lib.lists.optional cfg.cinny.enable cinny-desktop
      ++ lib.lists.optional cfg.fluffychat.enable fluffychat;
  };
}
