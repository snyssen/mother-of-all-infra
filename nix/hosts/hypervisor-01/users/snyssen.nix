{ flake, ... }:
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

  home.sessionVariables = {
    LIBVIRT_DEFAULT_URI = "qemu:///system";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "25.11";
}
