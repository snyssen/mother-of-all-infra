# Network configuration for the hypervisor host.
#
# A bridge interface (br0) is created and the physical NIC is enslaved to it.
# This allows virtual machines to attach their NICs directly to the LAN.
# The host's LAN IP is assigned to br0, not to the physical NIC.
#
# Rationale:
#   VMs need L2 access to the local network. By bridging the physical NIC,
#   any VM with a NIC attached to br0 appears as a first-class host on the LAN
#   and can obtain a DHCP lease or be assigned a static IP independently,
#   without requiring NAT or port-forwarding on the hypervisor.
#
# To change the physical NIC:
#   Set `lanNic` below to match the actual interface name shown by `ip link`.
#   Common alternatives: "enp3s0", "eth0".
{ ... }:
let
  # Physical NIC to enslave to the bridge.
  # Override this value if the actual interface name differs.
  lanNic = "enp5s0";
in
{
  networking.bridges.br0.interfaces = [ lanNic ];

  networking.interfaces = {
    # The bridge interface obtains the host's LAN IP via DHCP.
    br0.useDHCP = true;

    # The physical NIC is enslaved to br0; it must not hold an IP itself.
    "${lanNic}".useDHCP = false;
  };
}
