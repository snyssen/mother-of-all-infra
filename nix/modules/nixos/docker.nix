{ lib, config, ... }:
let
  cfg = config.docker;
in
{
  options.docker = {
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "snyssen" ];
    };
  };

  config = {
    virtualisation.docker.enable = true;
    users.extraGroups.docker.members = cfg.users;
  };
}
