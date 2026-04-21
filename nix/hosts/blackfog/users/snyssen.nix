{
  inputs,
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

  git.signingKeyFilename = "id_ed25519.pub";

  vscode.useUnstable = true;

  rclone.gui.enable = true;

  programs.btop.enable = true;
  programs.bat.enable = true;

  home.packages = with pkgs; [
    librewolf
    onlyoffice-desktopeditors
    protonmail-desktop
    vlc
    annotator
    moonlight-qt
    gradia
    dbeaver-bin
    remmina
    postgresql
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
