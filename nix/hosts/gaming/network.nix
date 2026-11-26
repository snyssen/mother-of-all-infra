# Configuration copied from hypervisor-01, see hypervisor-01 for explanations
{ ... }:
let
  # Physical NIC to enslave to the bridge.
  # Override this value if the actual interface name differs.
  lanNic = "enp2s0";
in
{
  networking = {
    useNetworkd = true;
    useDHCP = false;

    # Avoid another DHCP client racing with networkd on this host.
    dhcpcd.enable = false;

    # Unlike hypervisor-01, this host runs a desktop: COSMIC enables NetworkManager,
    # which would otherwise auto-create a "Wired connection" on the physical NIC and
    # run DHCP on it, racing networkd. When it wins, the bridge port ends up holding
    # its own lease (e.g. 192.168.1.131) next to br0's, and routing breaks.
    # NetworkManager stays enabled for the desktop applet, but keeps its hands off
    # the bridge and its port.
    networkmanager.unmanaged = [
      "interface-name:${lanNic}"
      "interface-name:br0"
    ];

    firewall = {
      enable = true;
    };

    bridges.br0.interfaces = [ lanNic ];
    interfaces = {
      # The bridge interface obtains the host's LAN IP via DHCP.
      br0.useDHCP = true;

      # The physical NIC is enslaved to br0; it must not hold an IP itself.
      "${lanNic}".useDHCP = false;
    };
  };
  systemd.network.networks."10-${lanNic}" = {
    matchConfig.Name = lanNic;
    networkConfig = {
      Bridge = "br0";
      DHCP = "no";
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };
  systemd.network.networks."20-br0" = {
    matchConfig.Name = "br0";
    networkConfig.DHCP = "yes";
    dhcpV4Config.UseDomains = "yes"; # get .lan etc working
  };
}
