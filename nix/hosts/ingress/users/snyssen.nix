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
    flake.modules.home.zsh
    flake.modules.home.git
  ];

  zsh.fzf.enable = true;
  zsh.intelli-shell.enable = true;

  git.signingKeyFilename = "id_ed25519.pub";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
