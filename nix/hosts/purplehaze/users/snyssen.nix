{
  flake,
  pkgs,
  ...
}:
{

  #
  ## WORKAROUNDS
  #

  #########################

  imports = [
    flake.modules.home.dconf
    flake.modules.home.shell
    flake.modules.home.ghostty
    flake.modules.home.git
    flake.modules.home.vscode
    flake.modules.home.firefox
    flake.modules.home.obsidian
    flake.modules.home.rclone
    flake.modules.home.vesktop
  ];

  # specialisation = {
  #   gnome.configuration = {
  #     myHomeManager.dconf.enable = true;
  #   };
  # };

  git.signingKeyFilename = "id_ed25519.pub";

  vscode.useUnstable = true;

  rclone.gui.enable = true;

  # obsidian.vaults.manage = true;

  # TODO: move
  home.packages = with pkgs; [
    sweethome3d.application
    librewolf
    onlyoffice-desktopeditors
    protonmail-desktop
    picard
    vlc
    annotator
    element-desktop
    fluffychat
    moonlight-qt
    gradia
    dbeaver-bin
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
