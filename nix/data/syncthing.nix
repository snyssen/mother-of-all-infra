let
  # The Nix hosts accept Syncthing connections on their tailnet interface (the
  # syncthing module's openTailnetFirewall), but discovery can't tell peers that: LAN
  # discovery doesn't cross Tailscale, and global discovery only learns the home
  # router's public address. So their tailnet (MagicDNS) name comes first; `dynamic`
  # adds whatever discovery finds, and relays as a last resort.
  onTailnet = name: id: {
    inherit id;
    addresses = [
      "tcp://${name}:22000"
      "quic://${name}:22000"
      "dynamic"
    ];
  };
in
{
  devices = {
    # Not managed from Nix: discovery and relays only.
    "sync.snyssen.be" = {
      id = "6QHAMO3-PARP6UW-3Y5J7I4-P5PN2C5-RHS6OMP-QCSBP5Z-6OBZMC3-NZM65QT";
    };
    "Pixel 8 Pro" = {
      id = "DLXNSVV-GZGRYS7-JAZ5KLW-R3DSKMX-NHNUZYL-Y43OE6C-XC2ZNFN-5FEPQA4";
    };

    "gaming" = onTailnet "gaming" "VKCNNIQ-QHLF7AM-D2R4JML-MFR27ZA-CWUCRIC-JPI4M3W-5IGSPAT-UXJKFQQ";
    "sninful" = onTailnet "sninful" "RUPVKFS-XBNCXTY-ZFZN2I5-ECOMFQX-V74LTZR-JSN4BVS-BOTA235-S6Z7FQT";
    "purplehaze" =
      onTailnet "purplehaze" "P2ECEG6-RRB6YZI-KFYZUBF-FBHSUSA-DQUZXH2-MCQXI3Z-HMFUPDV-7ACNIAJ";
    "blackfog" = onTailnet "blackfog" "EDMGHVH-55SKSKP-OHIK7JD-T4FZEAG-EHTZVCX-VT5W7CI-2OIGIFH-LMYQKAG";
    # Identity generated ahead of deploy and kept in sops (nix/hosts/apps/data/syncthing.yaml),
    # so this ID is stable across rebuilds. Also open on every interface
    # (openFirewall), as the always-on peer LAN devices can reach too.
    "apps" = onTailnet "apps" "CXWSL3E-MBCAS7N-CWMRP7O-FKY5JZZ-DOGS7RZ-YQPGHTV-NDGG42H-IMWAMQS";
  };
}
