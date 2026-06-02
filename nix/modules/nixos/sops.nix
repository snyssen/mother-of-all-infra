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

  options.sops = {
    defaultSshKeys = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "host"
          "user"
          "both"
        ];
        default = "host";
      };
      hostKeyPath = lib.mkOption {
        type = lib.types.str;
        default = "/etc/ssh/ssh_host_ed25519_key";
        description = "Path to the default host SSH key to use for sops age encryption. Only used if defaultSshKeys.mode is 'host' or 'both'.";
      };
      userKeyPath = lib.mkOption {
        type = lib.types.str;
        default = "/home/snyssen/.ssh/id_ed25519";
        description = "Path to the default user SSH key to use for sops age encryption. Only used if defaultSshKeys.mode is 'user' or 'both'.";
      };
    };
    extraSshKeyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional SSH key paths to use for sops age encryption, in addition to the default keys specified in defaultSshKeys. This can be used to add extra keys without changing the default ones.";
    };
  };

  config = {
    sops = {
      defaultSopsFile = ../../hosts/${config.system.name}/data/secrets.yaml;
      age.sshKeyPaths =
        [ ]
        ++ lib.lists.optional (
          cfg.defaultSshKeys.mode == "host" || cfg.defaultSshKeys.mode == "both"
        ) cfg.defaultSshKeys.hostKeyPath
        ++ lib.lists.optional (
          cfg.defaultSshKeys.mode == "user" || cfg.defaultSshKeys.mode == "both"
        ) cfg.defaultSshKeys.userKeyPath
        ++ cfg.extraSshKeyPaths;
      age.generateKey = true;
    };
  };
}
