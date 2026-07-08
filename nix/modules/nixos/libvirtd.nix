{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.libvirtd;
in
{
  options.libvirtd = {
    enable = lib.mkEnableOption "libvirtd virtualization daemon";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "snyssen" ];
      description = "Users to add to the libvirtd and kvm groups.";
    };

    # TODO: make this more fine-grained, e.g. allow VNC from specific IP ranges instead of entire LAN
    vncLanAccess = lib.mkEnableOption "VNC access from LAN (opens firewall ports 5900-5910; default: SSH tunnel only)";

    windowsGuestSupport = lib.mkEnableOption "Windows-friendly guest support (TPM and virtio driver ISO package)";

    desktopClientSupport = lib.mkEnableOption "desktop-oriented client support (SPICE USB redirection and virt-viewer)";
  };

  config = lib.mkIf cfg.enable {
    # Give configured users access to the libvirt socket and KVM device
    users.extraGroups.libvirtd.members = cfg.users;
    users.extraGroups.kvm.members = cfg.users;

    programs.virt-manager.enable = true;

    virtualisation.libvirtd = {
      enable = true;
      allowedBridges = [ "br0" ];
      qemu = {
        runAsRoot = true;
        swtpm.enable = cfg.windowsGuestSupport;
        vhostUserPackages = with pkgs; [
          virtiofsd
        ];
      };
    };

    virtualisation.spiceUSBRedirection.enable = cfg.desktopClientSupport;

    # Ensure Python3 is available for Ansible
    environment.systemPackages =
      with pkgs;
      [
        python3
      ]
      ++ lib.optionals cfg.desktopClientSupport [
        virt-viewer
        quickemu
      ]
      ++ lib.optionals cfg.windowsGuestSupport [
        virtio-win
      ];

    # Drivers
    hardware.graphics.enable = true;

    # Open VNC ports if LAN access is enabled
    networking.firewall.allowedTCPPorts = lib.optionals cfg.vncLanAccess (lib.range 5900 5910);
  };
}
