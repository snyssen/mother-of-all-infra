# Setup a New Machine

## Initial Setup

### 1. Prepare NixOS config

Easiest way is to copy an existing machine config. Choose the new machine hostname and create a directory `nix/hosts/${new_machine_name}/`. Then create:

- `configuration.nix`: the main config file
- `hardware-configuration.nix`: hardware specific configuration. It will be generated, but you need a placeholder one to get started; just copy one from another machine
- `users/${username}.nix`: home manager config for the specified user

### 2. Boot The New Machine on The NixOS Minimal Image

Prepare a bootable USB with the [NixOS minimal image](https://nixos.org/download/). [Ventoy](https://www.ventoy.net/en/index.html) is a great choice for this. Then boot the new machine off it.

### 3. Prepare Live Environment

We need to be able to SSH as root on the new machine from another machine that has Nix installed. Detailed instructions can be found in the [NixOS manual](https://nixos.org/manual/nixos/stable/#sec-installation-manual), but the operations usually boils down to:

1. Change the keyboard layout if needed (makes every subsequent operation easier), e.g. for belgian layout: `sudo loadkeys /etc/kbd/keymaps/i386/azerty/be-latin1.map.gz`
2. Connect to Wifi if needed: call `nmtui` then follow on-screen instructions
3. Set root password: `sudo passwd`; ssh server is automatically enabled by the installer, so you should now be able to login as root using the password you just set
4. `ip addr` to retrieve the machine's IP

Try to connect from the other machine: `ssh root@x.x.x.x` (with IP from step 4). If you connect successfully, `exit` and continue with instructions.

Check the disks inside the new machine with `lsblk` and confirm that they correspond with the disks you are targeting with your [disko](https://github.com/nix-community/disko) config. If your config is ready (you can try building it with `nh os build -H ${new_machine_name}`), you are ready for formatting the new machine.

### 4. Format The New Machine With nixos-anywhere

[nixos-anywhere](https://nix-community.github.io/nixos-anywhere/quickstart.html) is used to install our configuration on the new machine.

1. If you have LUKS enabled, prepare the password: `echo "my-super-safe-password" > /tmp/secret.key`, as well as the keyfile (see [Create The Keyfile](./Full%20Disk%20Encryption.md#Create%20The%20Keyfile), then copy resulting file to the new machine `scp /tmp/${new_machine_name} root@x.x.x.x:/key/${new_machine_name}`)
2. Run the nixos-anywhere command:

```sh
nix run github:nix-community/nixos-anywhere -- \
    --flake .#${new_machine_name} --target-host root@x.x.x.x \
    --generate-hardware-config nixos-generate-config ./hosts/${new_machine_name}/hardware-configuration.nix \
    --disk-encryption-keys /tmp/secret.key /tmp/secret.key
```

(do not include that last flag if you are not using LUKS)

nixos-anywhere will ask for the SSH password, but you can then go grab a coffee as this will take a few minutes. Upon returning, the new machine should be ready for use. Once the command is done, your new machine should automatically reboot. Log into your new NixOS setup and don't forget to change the default user password (usually "123456789")!

## Post Setup Actions

### Generate your SSH keys and allow access to SOPS

TODO

### Log into attic cache

On the server running attic, generate a new token:

```sh
docker exec attic atticadm make-token -f /attic/attic.toml --sub snyssen --validity 365d --create-cache "snyssen-*" --push "snyssen-*" --pull "snyssen-*" --configure-cache "snyssen-*"
```

Then, back on your new machine, log into attic

```sh
attic login snyssen-infra https://attic.snyssen.be $ATTIC_TOKEN
```
