{ config, ... }:
let
  cfg = config.sops;
in
{
  options.sops = { };

  config = {
    sops = {
      defaultSopsFile = ../../data/test.yaml;
      age.sshKeyPaths = [ "/home/snyssen/.ssh/id_ed25519" ];
      age.generateKey = true;
    };
  };
}
