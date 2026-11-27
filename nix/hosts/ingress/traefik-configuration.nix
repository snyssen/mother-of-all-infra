{
  lib,
  config,
  inputs,
  ...
}:
let
  appsServerIp = "100.114.242.89";
  # Module path of the CrowdSec bouncer plugin, which is also where Traefik looks for its
  # sources: ./plugins-local/src/<module path>, relative to its working directory.
  crowdsecPluginModule = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin";
  # Public routers that skip CrowdSec AppSec (the crowdsec-waf middleware) entirely.
  # Give the reason next to each one.
  wafExempt = [ ];
  # Paths that skip AppSec on an otherwise covered router: a second router per entry,
  # same service, without the middleware. Both are server-to-server federation, where a
  # false positive silently breaks federation instead of showing anyone an error.
  wafExemptPaths = {
    # Synapse federation and server keys. The client API stays covered.
    matrix = "PathPrefix(`/_matrix/federation`) || PathPrefix(`/_matrix/key`)";
    # Sharkey's ActivityPub inboxes (shared and per user): a third of ingress's traffic
    # and most of its request bodies. The web UI, API and media stay covered.
    social = "Path(`/inbox`) || PathRegexp(`^/users/[^/]+/inbox$`)";
  };
  # These allow proxying web services to the apps server without middleware or complex rules.
  # Unlike the TCP/UDP definitions below, HTTP backends are configured from these hostnames
  # (for example as `https://${hostname}`), so ingress must resolve them via split-horizon or
  # tailnet DNS to the apps server. Do not use public DNS for backend resolution here.
  # If you need more complex rules, you can add them directly to
  # services.traefik.dynamicConfigOptions.http.routers and
  # services.traefik.dynamicConfigOptions.http.services options below.
  proxiedWebServices = {
    auth-main = "auth.snyssen.be";
    auth-team = "auth.bigdouf.team";
    dashboard = "dash.snyssen.be";
    mc-dynmap = "mc.snyssen.be";
    # mc-usw-dynmap = "mc-usw.snyssen.be"; # dynmap for USW server
    element = "element.snyssen.be";
    foundryvtt = "dnd.snyssen.be";
    immich = "photos.snyssen.be";
    jellyfin = "streaming.snyssen.be";
    matrix-mas = "matrix-mas.snyssen.be";
    matrix = "matrix.snyssen.be";
    nextcloud = "cloud.snyssen.be";
    personal-website = "snyssen.be";
    rallly = "events.bigdouf.team";
    recipes = "recipes.snyssen.be";
    pdf = "pdf.snyssen.be";
    social = "social.snyssen.be";
    speedtest = "speedtest.snyssen.be";
    team = "bigdouf.team";
    umami = "umami.snyssen.be";
    dawarich = "location.snyssen.be";
    argunix = "argunix.snyssen.be";
  };
  proxiedTCPServices = {
    minecraft = {
      address = appsServerIp;
      port = 25565;
    };
  };
  proxiedUDPServices = {
    # example-udp-service = {
    #   address = appsServerIp;
    #   port = 12345;
    # };
  };
in
{
  traefik.ping.enable = true;

  # CrowdSec AppSec (WAF) for the public routes. Only the bouncer plugin runs here; the
  # rules run in apps-01's CrowdSec, reached over the tailnet. See
  # docs/plans/crowdsec-appsec.md.
  #
  # The key is read by the plugin itself, as a file, so it stays out of the store. Same
  # value as apps-01's compose-stacks/crowdsec/ingress_waf_bouncer/api_key.
  sops.secrets."crowdsec/appsec_key" = {
    owner = "traefik";
    mode = "0400";
    restartUnits = [ "traefik.service" ];
  };
  # Plugin sources from the store, pinned in flake.nix, rather than downloaded at
  # startup: a failed download disables every plugin for the life of the process (see
  # the localPlugins note in apps-01's compose/reverse-proxy/docker-compose.yaml).
  #
  # Every parent directory is declared owned by traefik: left implicit, tmpfiles
  # creates them owned by root inside traefik's data dir, then refuses to traverse them
  # ("unsafe path transition") and never creates the link. Traefik then disables all
  # plugins and drops every router that uses one: every public site 404s.
  systemd.tmpfiles.rules =
    let
      base = "${config.services.traefik.dataDir}/plugins-local";
      parents = lib.init (lib.splitString "/" "src/${crowdsecPluginModule}");
      parentDirs = lib.imap1 (i: _: "${base}/${lib.concatStringsSep "/" (lib.take i parents)}") parents;
    in
    map (dir: "d ${dir} 0755 traefik traefik - -") ([ base ] ++ parentDirs)
    ++ [
      "L+ ${base}/src/${crowdsecPluginModule} - - - - ${inputs.crowdsec-bouncer-traefik-plugin}"
    ];
  # Plugins load only at startup, and the link lives outside the unit: restart Traefik
  # whenever the plugin's store path changes (first deploy, version bump).
  systemd.services.traefik.restartTriggers = [ inputs.crowdsec-bouncer-traefik-plugin ];
  services.traefik.staticConfigOptions.experimental.localPlugins.crowdsec-bouncer.moduleName =
    crowdsecPluginModule;

  traefik.tcpEntrypoints = lib.mapAttrs (_: svc: {
    port = svc.port;
  }) proxiedTCPServices;

  traefik.udpEntrypoints = lib.mapAttrs (_: svc: {
    port = svc.port;
  }) proxiedUDPServices;
  services.traefik.dynamicConfigOptions = {
    http.middlewares = {
      ip-allowlist = {
        ipAllowList.sourceRange = [
          # Home
          # "213.49.36.74/32"
          # tailnet
          "100.64.0.0/10"
        ];
      };
      # `appsec` mode: AppSec checks only, no per-request decision lookups, since this
      # host's crowdsec-firewall-bouncer already enforces bans.
      crowdsec-waf.plugin.crowdsec-bouncer = {
        enabled = true;
        crowdsecMode = "appsec";
        crowdsecAppsecEnabled = true;
        # apps-01's Traefik, which routes it to the listener on 7423 (see the
        # crowdsec-appsec-ingress router in apps-01's compose/crowdsec/default.nix).
        # Resolved like the backends below, through the split-horizon wildcard.
        crowdsecAppsecScheme = "https";
        crowdsecAppsecHost = "appsec.snyssen.be";
        crowdsecAppsecPath = "/";
        crowdsecAppsecKeyFile = config.sops.secrets."crowdsec/appsec_key".path;
        # 1 MiB of each body is inspected; 10 MiB by default.
        crowdsecAppsecBodyLimit = 1048576;
        # Bodies that cannot be buffered (no Content-Length) go through with a
        # headers-only check instead of being blocked.
        crowdsecAppsecUnreadableBodyBlock = false;
        # Fail open while the trial runs; decided in Phase 3 of the plan.
        crowdsecAppsecFailureBlock = false;
        crowdsecAppsecUnreachableBlock = false;
      };
    };
    http.routers = lib.mkMerge [
      {
        traefik-dashboard = {
          entryPoints = [ "websecure" ];
          rule = "Host(`ingress.snyssen.be`)";
          service = "api@internal";
          middlewares = [ "ip-allowlist" ];
        };
        ping = {
          entryPoints = [ "websecure" ];
          rule = "Host(`ingress.snyssen.be`) && Path(`/ping`)";
          service = "ping@internal";
        };
        prometheus-node-exporter = {
          entryPoints = [ "websecure" ];
          rule = "Host(`pne.ingress.snyssen.be`)";
          service = "prometheus-node-exporter";
          middlewares = [ "ip-allowlist" ];
        };
      }
      (lib.mapAttrs (svcName: hostname: {
        entryPoints = [ "websecure" ];
        rule = "Host(`${hostname}`)";
        service = svcName;
        middlewares = lib.optional (!lib.elem svcName wafExempt) "crowdsec-waf";
      }) proxiedWebServices)
      (lib.mapAttrs' (
        svcName: paths:
        lib.nameValuePair "${svcName}-waf-exempt" {
          entryPoints = [ "websecure" ];
          rule = "Host(`${proxiedWebServices.${svcName}}`) && (${paths})";
          service = svcName;
          # Above the router it carves paths out of, whatever the rules' lengths.
          priority = 1000;
        }
      ) wafExemptPaths)
    ];
    http.services = lib.mkMerge [
      {
        prometheus-node-exporter = {
          loadBalancer.servers = [
            { url = "http://localhost:9100"; }
          ];
        };
      }

      (lib.mapAttrs (svcName: hostname: {
        loadBalancer = {
          servers = [
            { url = "https://${hostname}"; }
          ];
          passHostHeader = false;
        };
      }) proxiedWebServices)
    ];
  }
  // lib.optionalAttrs (proxiedTCPServices != { }) {
    tcp.routers = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ svcName ];
        rule = "HostSNI(`*`)";
        service = svcName;
      }) proxiedTCPServices)
    ];
    tcp.services = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${toString svc.port}"; }
          ];
        };
      }) proxiedTCPServices)
    ];
  }
  // lib.optionalAttrs (proxiedUDPServices != { }) {
    udp.routers = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ svcName ];
        service = svcName;
      }) proxiedUDPServices)
    ];
    udp.services = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${toString svc.port}"; }
          ];
        };
      }) proxiedUDPServices)
    ];
  };
}
