{ config, lib, ... }:
let
  cfg = config.sops;
in
{
  options.sops = { };

  config = {
    sops = {
      defaultSopsFile = ../../data/secrets.yaml;
      age.sshKeyPaths = lib.mkDefault [ "/home/snyssen/.ssh/id_ed25519" ];
      age.generateKey = true;
    };
  };
}
