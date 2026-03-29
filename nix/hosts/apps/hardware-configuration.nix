# This is a stub hardware configuration for the apps VM.
# It will be replaced by the auto-generated file from 'nixos-generate-config'
# after the first boot on the hypervisor.
#
# To regenerate on the deployed VM:
#   nixos-generate-config --show-hardware-config
# Then copy the output here and remove this header comment.
{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "virtio_pci"
    "xhci_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
