# Static LAN address: 192.168.1.10, the legacy prod box's, so the split-horizon
# records that send the LAN to `snyssen.be`, `*.snyssen.be` and `bigdouf.team`
# (ansible/hosts/group_vars/technitium/vars.yml) need no change at the cutover. Inside
# the DHCP scope's exclusion range (.1-.20), like technitium-secondary's .3.
#
# Matched on the MAC set in ansible/hosts/host_vars/hypervisor-01/vars.yml rather than
# on the interface name: the name follows the VM's PCI layout (enp4s0 on the test
# hypervisor), which a GPU or virtiofs device can shift.
{ ... }:
{
  networking.useNetworkd = true;

  systemd.network.networks."20-lan" = {
    matchConfig.MACAddress = "52:54:00:00:00:01";
    networkConfig = {
      Address = "192.168.1.10/24";
      Gateway = "192.168.1.1";
      # The Technitium pair, over the LAN; see the resolver notes in configuration.nix.
      DNS = [
        "192.168.1.2"
        "192.168.1.3"
      ];
      Domains = "lan";
    };
  };
}
