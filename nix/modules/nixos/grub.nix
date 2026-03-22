{ lib, config, ... }:
let
  cfg = config.grub;
in
{
  options.grub = {
    timeout = lib.mkOption {
      default = 5;
      description = ''
        Duration (in seconds) until grub boots in default menu item.
      '';
    };
  };

  config = {
    boot.loader = {
      timeout = cfg.timeout;
      # efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        device = "nodev";
        useOSProber = true;
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
    };
  };
}
