{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/skyrim-together/Data 0755 0 0 -"
  ];

  # Carried over unchanged from the legacy vault, so players keep the password they
  # know.
  sops.secrets = {
    "compose-stacks/skyrim-together/password" = {
      sopsFile = ../../data/skyrim-together.yaml;
    };
    "compose-stacks/skyrim-together/admin_password" = {
      sopsFile = ../../data/skyrim-together.yaml;
    };
  };

  # Prod's STServer.ini, values unchanged. Root-only is enough: the image runs as root.
  sops.templates."skyrim-together-STServer.ini".content = ''
    [general]
    sLogLevel=info
    bConsole=true

    [LiveServices]
    bAnnounceServer=false

    [Gameplay]
    fGoldLossFactor=0
    bEnablePvp=true
    bEnableGreetings=true
    bEnableXpSync=true
    uDifficulty=3

    [ModPolicy]
    bAllowMO2=true
    bAllowSKSE=true
    bEnableModCheck=false

    [GameServer]
    sPassword=${config.sops.placeholder."compose-stacks/skyrim-together/password"}
    sAdminPassword=${config.sops.placeholder."compose-stacks/skyrim-together/admin_password"}
    sServerName=skyrim.${config.domains.main}
    uMaxPlayerCount=8
    uPort=10578
  '';

  sops.templates."compose-skyrim-together.env".content = ''
    SKYRIM_TOGETHER_CONFIG_PATH=${config.sops.templates."skyrim-together-STServer.ini".path}
  '';

  # The game is UDP, on the `skyrim-together` entrypoint declared in compose/reverse-proxy.
  reverseProxy.dynamicConfig.skyrim-together = ''
    udp:
      routers:
        skyrim-together:
          entryPoints:
            - skyrim-together
          service: skyrim-together
      services:
        skyrim-together:
          loadBalancer:
            servers:
              - address: "skyrim-together:10578"
  '';

  compose-stacks.stacks.skyrim-together = {
    restartTriggers = [
      config.sops.templates."skyrim-together-STServer.ini".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-skyrim-together.env".path;
    dockerNetworks = [ "web" ];
    # On demand, as the migration plan has it: started by hand for a session
    # (`systemctl start compose-skyrim-together`), not at boot.
    autostart = false;
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
