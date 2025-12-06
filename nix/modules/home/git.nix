{ lib, config, ... }:
let cfg = config.myHomeManager.git;
in {
  options.myHomeManager.git = {
    username = lib.mkOption { default = "snyssen"; };
    email = lib.mkOption { default = "dev@snyssen.be"; };
    signingKeyFilename = lib.mkOption { default = "id_rsa.pub"; };
  };

  programs.git = {
    enable = true;
    userName = cfg.username;
    userEmail = cfg.email;
    extraConfig = {
      # Sign all commits using ssh key
      commit.gpgsign = true;
      gpg.format = "ssh";
      user.signingkey = "~/.ssh/${cfg.signingKeyFilename}";
      pull.rebase = true;
    };
  };
}
