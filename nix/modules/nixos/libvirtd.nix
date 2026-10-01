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
      # Default ("suspend") managed-saves every running guest on host
      # shutdown/reboot and tries to resume them afterward — this is what broke
      # technitium-secondary's virtiofs state and haos's USB passthrough after a
      # hypervisor reboot: resuming a saved VM state assumes the exact same backend
      # state (virtiofsd process, USB device enumeration) the host had *before*
      # rebooting, which a fresh boot can't guarantee. "shutdown" does a graceful
      # ACPI shutdown of each guest before the host goes down instead, so every
      # guest always comes back via a genuine cold boot — slower, but with no stale
      # state to fail to resume from.
      onShutdown = "shutdown";
      # Shut guests down concurrently rather than one-by-one (the upstream default)
      # — no reason to serialize unrelated VMs just because the host is rebooting.
      parallelShutdown = 4;
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
