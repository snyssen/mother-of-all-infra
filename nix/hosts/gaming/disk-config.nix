{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme1n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted-main";
                settings.allowDiscards = true; # Allow TRIM operations on SSD
                passwordFile = "/tmp/secret.key";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
      game-ssd = {
        device = "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted-game-ssd";
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.key"; # Reuse key
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/game-ssd";
                };
              };
            };
          };
        };
      };
      game-hdd = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted-game-hdd";
                passwordFile = "/tmp/secret.key"; # Reuse key
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/game-hdd";
                };
              };
            };
          };
        };
      };
    };
  };
}
