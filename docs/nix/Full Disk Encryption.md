# Full Disk Encryption

Full disk encryption is enabled on the [Disko](https://github.com/nix-community/disko) configuration, e.g.

```nix
disko.devices = {
  disk = {
    main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ...
          luks = {
            size = "100%";
            label = "luks";
            content = {
              type = "luks";
              name = "luks";
              passwordFile = "/tmp/secret.key"; # Backup password, set at creation
              settings = { # Optional settings for decrypting using USB key
                keyFile = "/key/${cfg.keyFilename}"; # Keyfile, see creation later
                # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
                fallbackToPassword = true; # Allow password fallback if no key found
                # Mounts an USB key containing the keyfile
                preOpenCommands = ''
                  mkdir -m 0755 -p /key
                  echo "Trying to mount USB key for LUKS decryption..."
                  sleep 3 # Waiting for USB to be ready
                  ${lib.strings.concatMapStringsSep " || " (
                    id: "mount -n -t vfat -o ro -U ${id} /key"
                  ) cfg.usbKeysIds}
                '';
              };
              content = {
                ...
              };
            };
          };
        };
      };
    };
  };
};
```

## Decryption Using Keyfile Stored on USB Key

The code snippet above shows how a LUKS partition can be configured in Disko to allow decrypting it from a key stored in a VFAT-formatted USB key. Here is how you can setup such a key:

### Format The USB key to VFAT/FAT32

I usually do this using gparted; I won't explain it here as it is trivial.

### Create The Keyfile

Mount the key and go at its root (easiest way is using your file explorer and using the "Open in Terminal" option), then run the following command:

```sh
sudo dd if=/dev/urandom of=./KEYFILENAME bs=512 count=1
```

I like to use the target machine name as the keyfile name. It should correspond with the keyfile name provided in the Disko config.

### Add The Keyfile in LUKS

On the target machine, allow the keyfile to unlock the partition:

```sh
sudo cryptsetup luksAddKey /dev/sdb1 ./KEYFILENAME
```

**Replace `/dev/sdb1` with whatever your LUKS partition is**. You can figure out the partition name using `lsblk`, e.g.:

```sh
$ lsblk
NAME                 MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
sda                    8:0    0   1,8T  0 disk
sdb                    8:16   0 111,8G  0 disk
└─sdb1                 8:17   0 111,8G  0 part
  └─crypted-game-ssd 254:1    0 111,8G  0 crypt /mnt/game-ssd
sdc                    8:32   0 465,8G  0 disk
└─sdc1                 8:33   0 465,8G  0 part
  └─crypted-game-hdd 254:0    0 465,7G  0 crypt /mnt/game-hdd
sdd                    8:48   1   3,8G  0 disk
└─sdd1                 8:49   1   3,8G  0 part  /run/media/snyssen/9FBA-884A
nvme0n1              259:0    0   1,8T  0 disk
├─nvme0n1p1          259:1    0   500M  0 part  /boot
└─nvme0n1p2          259:2    0   1,8T  0 part
  └─crypted-main     254:2    0   1,8T  0 crypt /nix/store
                                                /
```

In the output above, the LUKS partitions can be foud at `/dev/nvme0n1p2` (crypted-main), `/dev/sdb1` (crypted-game-ssd) and `/dev/sdc1` (crypted-game-hdd)
