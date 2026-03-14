{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.libvirtd;
  nixvirt = inputs.NixVirt;

  vmVolumes = lib.mapAttrsToList (name: vm: {
    definition = nixvirt.lib.volume.writeXML {
      name = "${name}.qcow2";
      capacity = {
        count = vm.diskSizeGiB;
        unit = "GiB";
      };
      target.format.type = "qcow2";
    };
  }) cfg.vms;

  vmDomains = lib.mapAttrsToList (name: vm: {
    definition = nixvirt.lib.domain.writeXML (
      nixvirt.lib.domain.templates.linux {
        inherit name;
        uuid = vm.uuid;
        vcpu = { count = vm.vcpus; };
        memory = {
          count = vm.memoryGiB;
          unit = "GiB";
        };
        storage_vol = {
          pool = "vmstore";
          volume = "${name}.qcow2";
        };
        bridge_name = vm.bridge;
      }
    );
  }) cfg.vms;
in
{
  imports = [
    nixvirt.nixosModules.default
  ];

  options.libvirtd = {
    enable = lib.mkEnableOption "libvirtd virtualization daemon";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "snyssen" ];
      description = "Users to add to the libvirtd and kvm groups.";
    };

    vmstorePath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/vmstore";
      description = "Path to the directory used as the libvirt vmstore storage pool.";
    };

    vms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            uuid = lib.mkOption {
              type = lib.types.str;
              description = "Stable UUID for the libvirt domain (generate once with uuidgen).";
            };
            vcpus = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2;
              description = "Number of virtual CPUs.";
            };
            memoryGiB = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2;
              description = "Amount of RAM in GiB.";
            };
            diskSizeGiB = lib.mkOption {
              type = lib.types.ints.positive;
              description = "Disk image size in GiB (created in vmstorePath if absent).";
            };
            bridge = lib.mkOption {
              type = lib.types.str;
              default = "br0";
              description = "Network bridge to attach the VM NIC to.";
            };
          };
        }
      );
      default = { };
      description = "Declarative libvirt VM definitions managed via NixVirt.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        # Software TPM for guests that need a TPM device
        swtpm.enable = true;
      };
    };

    # Give configured users access to the libvirt socket and KVM device
    users.extraGroups.libvirtd.members = cfg.users;
    users.extraGroups.kvm.members = cfg.users;

    programs.virt-manager.enable = true;

    virtualisation.libvirt = lib.mkIf (cfg.vms != { }) {
      enable = true;
      connections."qemu:///system" = {
        pools = [
          {
            definition = nixvirt.lib.pool.writeXML {
              type = "dir";
              name = "vmstore";
              target.path = cfg.vmstorePath;
            };
            active = true;
            volumes = vmVolumes;
          }
        ];
        domains = vmDomains;
      };
    };
  };
}
