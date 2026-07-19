{ flake, pkgs, ... }:
{
  #
  ## WORKAROUNDS
  #

  # prevent hibernation due to power issues with NVIDIA cards
  dconf.settings."org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
  dconf.settings."org/gnome/settings-daemon/plugins/power".sleep-inactive-battery-type = "suspend";

  #########################

  imports = [
    flake.modules.home.shell
    flake.modules.home.ghostty
    flake.modules.home.git
    flake.modules.home.vscode
    flake.modules.home.firefox
    flake.modules.home.obsidian
    flake.modules.home.vesktop

    flake.modules.home.restic-dr
  ];

  git.signingKeyFilename = "id_ed25519.pub";

  vscode.useUnstable = true;

  programs.btop.enable = true;
  programs.bat.enable = true;

  home.packages = with pkgs; [
    sweethome3d.application
    librewolf
    onlyoffice-desktopeditors
    protonmail-desktop
    # caligula
    # zenity
    p7zip
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
