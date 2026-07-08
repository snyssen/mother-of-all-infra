# libvirtd Nix Module

This module wraps NixOS libvirt defaults used in this repository and adds host-level convenience options.

Path: `nix/modules/nixos/libvirtd.nix`

## Base behavior

Enable the module on a host to get:

- `virtualisation.libvirtd.enable = true`
- `programs.virt-manager.enable = true`
- configured users added to `libvirtd` and `kvm` groups
- `virtiofsd` support for virtiofs workloads
- optional LAN VNC port opening via `libvirtd.vncLanAccess`

## Options

### `libvirtd.enable`

Enables this module.

### `libvirtd.users`

Users added to `libvirtd` and `kvm` groups.

Default:

```nix
[ "snyssen" ]
```

### `libvirtd.vncLanAccess`

When enabled, opens TCP ports `5900-5910` in the host firewall.

Default: `false`

### `libvirtd.windowsGuestSupport`

Optional Windows guest support. Keeps hypervisor defaults unchanged unless explicitly enabled.

When enabled:

- `virtualisation.libvirtd.qemu.swtpm.enable = true` (for TPM-backed guests such as Windows 11)
- `virtio-win` package is installed on the host so virtio drivers are available during Windows install

Default: `false`

### `libvirtd.desktopClientSupport`

Optional desktop UX support for local workstation hosts.

When enabled:

- `virtualisation.spiceUSBRedirection.enable = true`
- `virt-viewer` is installed

Default: `false`

## Host profiles

### Hypervisor host(s)

Typical hypervisor setup should keep optional workstation features disabled unless needed:

```nix
libvirtd = {
  enable = true;
  vncLanAccess = true;
};
```

### Desktop/workstation host (example: Blackfog)

For local desktop VM workflows in Cosmic:

```nix
libvirtd = {
  enable = true;
  windowsGuestSupport = true;
  desktopClientSupport = true;
};
```

This keeps VM networking on the default libvirt NAT network unless you explicitly configure host bridges.

## Windows 11 notes

For a Windows 11 VM created in `virt-manager`:

- choose UEFI firmware in VM settings
- attach TPM 2.0 in VM settings
- attach the `virtio-win` ISO to load paravirtualized storage/network drivers during install
- install SPICE guest tools in Windows if you want better desktop integration
