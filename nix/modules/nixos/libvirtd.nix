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

    vmstorePool = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to define and autostart the 'vmstore' storage pool.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/vmstore";
        description = "Filesystem path used as the libvirt 'vmstore' storage pool target.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # UEFI firmware for modern guests
        ovmf.enable = true;
        # Software TPM for guests that need a TPM device
        swtpm.enable = true;
      };
    };

    # Give configured users access to the libvirt socket and KVM device
    users.extraGroups.libvirtd.members = cfg.users;
    users.extraGroups.kvm.members = cfg.users;

    # Ensure the vmstore pool is defined, set to autostart, and started
    systemd.services.libvirt-setup-vmstore-pool = lib.mkIf cfg.vmstorePool.enable {
      description = "Configure libvirt 'vmstore' storage pool at ${cfg.vmstorePool.path}";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirtd.service" ];
      requires = [ "libvirtd.service" ];
      path = [ pkgs.libvirt ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RequiresMountsFor = [ cfg.vmstorePool.path ];
      };
      script = ''
        poolPath="${cfg.vmstorePool.path}"

        # Define the pool if it does not already exist
        if ! virsh pool-info vmstore >/dev/null 2>&1; then
          virsh pool-define-as vmstore dir --target "$poolPath"
        fi

        # Build the pool metadata (creates the target directory if absent);
        # ignore "already exists" errors, propagate unexpected ones
        buildOut=$(virsh pool-build vmstore 2>&1) || {
          echo "$buildOut" | grep -qi "already exists" || { echo "$buildOut" >&2; exit 1; }
        }

        # Enable autostart so the pool survives reboots
        virsh pool-autostart vmstore

        # Start the pool; virsh pool-start is effectively idempotent —
        # it errors only when the pool is already running, which we ignore
        virsh pool-start vmstore 2>&1 | grep -v "already active" || true
      '';
    };
  };
}
