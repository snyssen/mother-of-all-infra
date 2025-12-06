{ lib, config, ... }:
let
  cfg = config.git;
in
{
  options.git = {
    username = lib.mkOption { default = "snyssen"; };
    email = lib.mkOption { default = "dev@snyssen.be"; };
    signingKeyFilename = lib.mkOption { default = "id_rsa.pub"; };
  };

  config = {
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = cfg.username;
          email = cfg.email;
        };
        # Sign all commits using ssh key
        commit.gpgsign = true;
        gpg.format = "ssh";
        user.signingkey = "~/.ssh/${cfg.signingKeyFilename}";
        pull.rebase = true;
      };
    };
  };
}
