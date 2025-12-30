{ lib, config, ... }:
let
  cfg = config.disko;
  layouts = lib.lists.map (x: builtins.replaceStrings [ ".nix" ] [ "" ] x) (
    builtins.attrNames (builtins.readDir ./layouts)
  );
in
{
  options.disko = {
    layout = lib.mkOption {
      type = lib.types.enum layouts;
    };
  };

  imports = lib.lists.map (x: ./layouts/${x}.nix) layouts;
}
