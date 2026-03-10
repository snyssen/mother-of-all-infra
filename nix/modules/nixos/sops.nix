{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.sops;
in
{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  options.sops = { };

  config = {
    sops = {
      defaultSopsFile = ../../data/secrets.yaml;
      age.sshKeyPaths = lib.mkDefault [ "/home/snyssen/.ssh/id_ed25519" ];
      age.generateKey = true;
    };
  };
}
