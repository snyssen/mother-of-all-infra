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
    flake.modules.home.shell
    flake.modules.home.git
  ];

  git.signingKeyFilename = "id_ed25519.pub";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
