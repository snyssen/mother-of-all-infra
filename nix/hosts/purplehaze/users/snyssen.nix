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
    flake.modules.home.zsh
    flake.modules.home.ghostty
    flake.modules.home.git
    flake.modules.home.vscode
    flake.modules.home.direnv
    flake.modules.home.firefox
  ];

  # specialisation = {
  #   gnome.configuration = {
  #     myHomeManager.dconf.enable = true;
  #   };
  # };

  zsh.fzf.enable = true;
  zsh.intelli-shell.enable = true;

  git.signingKeyFilename = "id_ed25519.pub";

  vscode.useUnstable = true;

  # TODO: move
  home.packages = with pkgs; [
    obsidian
    sweethome3d.application
    librewolf
    vesktop
    onlyoffice-desktopeditors
    protonmail-desktop
    picard
    vlc
    annotator
    element-desktop
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
