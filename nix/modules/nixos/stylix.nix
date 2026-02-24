{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.stylix;
in
{
  imports = [
    inputs.stylix.nixosModules.stylix
  ];

  options.stylix = {
    wallpaper = lib.mkOption {
      type = lib.types.path;
      example = "../../files/wallpapers/icy_pink_sunrise.jpg";
    };
    schemeName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of a base 16 scheme to pick from pkgs.base16-schemes.
        A gallery of schemes can be found at https://tinted-theming.github.io/tinted-gallery/
      '';
      example = "atelier-cave-light";
    };
    isLightTheme = lib.mkEnableOption "Should be a light theme; otherwise, is dark theme";
  };

  config = {
    stylix = {
      enable = true;
      image = cfg.wallpaper;
      base16Scheme = "${pkgs.base16-schemes}/share/themes/${cfg.schemeName}.yaml";
      polarity = if cfg.isLightTheme then "light" else "dark";
      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.fira-mono;
          name = "FiraMono Nerd Font Mono";
        };
      };
    };
  };
}
