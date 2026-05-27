{ ... }:
{
  networking.interfaces.enp2s0.useDHCP = false;

  systemd.network.networks."20-enp2s0" = {
    matchConfig.Name = "enp2s0";
    networkConfig = {
      Address = "192.168.1.3/24";
      Gateway = "192.168.1.1";
      DNS = [
        "9.9.9.9"
        "1.1.1.1"
      ];
    };
  };
}
