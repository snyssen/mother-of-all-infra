{ ... }:
let
  interface = "enp3s0";
in
{
  networking = {
    useNetworkd = true;
    firewall.enable = true;
    interfaces.${interface}.useDHCP = false;
  };

  systemd.network.networks."20-${interface}" = {
    matchConfig.Name = "${interface}";
    networkConfig = {
      Address = "192.168.1.2/24";
      Gateway = "192.168.1.1";
      DNS = [
        "9.9.9.9"
        "1.1.1.1"
      ];
    };
  };
}
