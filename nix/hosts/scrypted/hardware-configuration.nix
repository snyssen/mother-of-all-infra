# PLACEHOLDER — replace this entire file with the output of:
#   nixos-generate-config --show-hardware-config
# run on the scrypted VM after provisioning.
# NOTE: do NOT include fileSystems entries — those are managed by disko.
{
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
