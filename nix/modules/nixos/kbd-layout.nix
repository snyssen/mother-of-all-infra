{ lib, config, ... }:
let
  cfg = config.kbd-layout;
in
{
  options.kbd-layout = {
    layout = lib.mkOption {
      default = "fr";
      description = ''
        Keyboartd layout to apply
      '';
    };
    additionalLayouts = lib.mkOption {
      default = [ ];
      description = ''
        Additional keybaord layouts to apply
      '';
    };
  };

  config = {
    # Configure keymap in X11
    services.xserver =
      let
        layoutLst = [ cfg.layout ] ++ cfg.additionalLayouts;
      in
      {
        # Concatenate as e.g. "fr,be,us"
        xkb.layout = lib.strings.concatStringsSep "," layoutLst;
      };

    # Configure console keymap
    console.keyMap = cfg.layout;
  };
}
