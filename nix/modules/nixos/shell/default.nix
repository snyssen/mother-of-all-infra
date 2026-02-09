{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.shell;
  shellPkgs = {
    zsh = pkgs.zsh;
    fish = pkgs.fish;
  };
in
{
  options.shell = {
    default = lib.mkOption {
      type = lib.types.enum [
        "zsh"
        "fish"
      ];
      default = "zsh";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "snyssen" ];
    };
  };

  config = {
    programs.zsh.enable = cfg.default == "zsh";
    programs.fish.enable = cfg.default == "fish";

    users.users = lib.listToAttrs (
      lib.lists.map (user: {
        name = user;
        value = {
          shell = shellPkgs.${cfg.default};
        };
      }) cfg.users
    );
  };
}
