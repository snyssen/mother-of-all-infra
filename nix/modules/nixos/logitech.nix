{ pkgs, ... }:
{
  hardware.logitech.wireless.enable = true;
  environment.systemPackages = [
    pkgs.solaar
  ];
}
