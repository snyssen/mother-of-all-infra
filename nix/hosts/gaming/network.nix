# Configuration copied from hypervisor, see hypervisor for explanations
{ ... }:
let
  # Physical NIC to enslave to the bridge.
  # Override this value if the actual interface name differs.
  lanNic = "enp2s0";
in
{
  networking = {
    useNetworkd = true;

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
  systemd.network.networks."20-br0" = {
    matchConfig.Name = "br0";
    networkConfig.DHCP = "yes";
    dhcpV4Config.UseDomains = "yes"; # get .lan etc working
  };
}
