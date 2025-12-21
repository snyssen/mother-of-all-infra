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
    flake.modules.home.dconf
    flake.modules.home.zsh
    flake.modules.home.ghostty
    flake.modules.home.git
    flake.modules.home.vscode
    flake.modules.home.direnv
    flake.modules.home.firefox
  ];

  zsh.fzf.enable = true;
  zsh.intelli-shell.enable = true;

  git.signingKeyFilename = "id_ed25519.pub";

  vscode.useUnstable = true;

  home.packages = with pkgs; [
    prismlauncher
    dconf-editor
    retroarch-full
    sweethome3d.application
    obsidian
    librewolf
    vesktop
    onlyoffice-desktopeditors
    protonmail-desktop
    caligula
    zenity
    protontricks
    p7zip
    fluffychat
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
