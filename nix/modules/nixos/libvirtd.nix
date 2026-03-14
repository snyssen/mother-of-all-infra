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

    vms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            vcpus = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2;
              description = "Number of virtual CPUs to allocate.";
            };
            memoryMiB = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2048;
              description = "Amount of RAM to allocate, in MiB.";
            };
            diskPath = lib.mkOption {
              type = lib.types.strMatching "^/.*";
              description = "Absolute path to the VM disk image (qcow2).";
              example = "/mnt/vmstore/my-vm.qcow2";
            };
            diskSize = lib.mkOption {
              type = lib.types.strMatching "^[0-9]+[KMGT]$";
              default = "20G";
              description = "Size of the disk image to create if it does not already exist (e.g. \"20G\", \"50G\").";
            };
            bridge = lib.mkOption {
              type = lib.types.str;
              default = "br0";
              description = "Bridge interface to attach the VM NIC to.";
            };
            autostart = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to configure the VM to start automatically with the host.";
            };
          };
        }
      );
      default = { };
      description = "Declarative libvirt VM domain definitions. For each entry a systemd service is created that ensures the disk image exists and the domain is defined in libvirt.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # Software TPM for guests that need a TPM device
        swtpm.enable = true;
      };
      # TODO: we might need to set "br0" as an allowed bridge?
      # Below is the default value
      # allowedBridges = [ "virbr0" ];
    };

    # Give configured users access to the libvirt socket and KVM device
    users.extraGroups.libvirtd.members = cfg.users;
    users.extraGroups.kvm.members = cfg.users;

    programs.virt-manager.enable = true;

    systemd.services = lib.mkMerge [
      # Ensure the vmstore pool is defined, set to autostart, and started
      (lib.mkIf cfg.vmstorePool.enable {
        libvirt-setup-vmstore-pool = {
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
      })

      # For each declared VM, ensure the disk image exists and the domain is defined in libvirt
      (lib.mapAttrs' (
        name: vm:
        let
          domainXml = pkgs.writeText "libvirt-domain-${name}.xml" ''
            <domain type="kvm">
              <name>${name}</name>
              <memory unit="MiB">${toString vm.memoryMiB}</memory>
              <currentMemory unit="MiB">${toString vm.memoryMiB}</currentMemory>
              <vcpu placement="static">${toString vm.vcpus}</vcpu>
              <os>
                <type arch="x86_64" machine="q35">hvm</type>
                <boot dev="hd"/>
              </os>
              <features>
                <acpi/>
                <apic/>
                <vmport state="off"/>
              </features>
              <cpu mode="host-passthrough" check="none" migratable="on"/>
              <clock offset="utc">
                <timer name="rtc" tickpolicy="catchup"/>
                <timer name="pit" tickpolicy="delay"/>
                <timer name="hpet" present="no"/>
              </clock>
              <on_poweroff>destroy</on_poweroff>
              <on_reboot>restart</on_reboot>
              <on_crash>destroy</on_crash>
              <devices>
                <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
                <disk type="file" device="disk">
                  <driver name="qemu" type="qcow2" discard="unmap"/>
                  <source file="${vm.diskPath}"/>
                  <target dev="vda" bus="virtio"/>
                </disk>
                <interface type="bridge">
                  <source bridge="${vm.bridge}"/>
                  <model type="virtio"/>
                </interface>
                <channel type="unix">
                  <target type="virtio" name="org.qemu.guest_agent.0"/>
                </channel>
                <input type="tablet" bus="usb"/>
                <graphics type="vnc" port="-1" autoport="yes" listen="127.0.0.1">
                  <listen type="address" address="127.0.0.1"/>
                </graphics>
                <audio id="1" type="none"/>
                <video>
                  <model type="vga" vram="16384" heads="1" primary="yes"/>
                </video>
                <memballoon model="virtio"/>
                <rng model="virtio">
                  <backend model="random">/dev/urandom</backend>
                </rng>
              </devices>
            </domain>
          '';
        in
        lib.nameValuePair "libvirt-define-vm-${name}" {
          description = "Define libvirt VM '${name}'";
          wantedBy = [ "multi-user.target" ];
          after = [
            "libvirtd.service"
          ] ++ lib.optional cfg.vmstorePool.enable "libvirt-setup-vmstore-pool.service";
          requires = [ "libvirtd.service" ];
          path = [
            pkgs.libvirt
            pkgs.qemu
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RequiresMountsFor = [ (builtins.dirOf vm.diskPath) ];
          };
          script = ''
            # Create the qcow2 disk image if it does not already exist
            if [ ! -f "${vm.diskPath}" ]; then
              qemu-img create -f qcow2 "${vm.diskPath}" "${vm.diskSize}" \
                || { echo "ERROR: failed to create disk image for VM '${name}' at '${vm.diskPath}' (size: ${vm.diskSize})" >&2; exit 1; }
            fi

            # Define (or redefine) the domain from the generated XML
            virsh define "${domainXml}"

            # Configure autostart
            ${if vm.autostart then "virsh autostart ${name}" else "virsh autostart --disable ${name}"}
          '';
        }
      ) cfg.vms)
    ];
  };
}
