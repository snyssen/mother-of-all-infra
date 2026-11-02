{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  # The image sets no USER, so the server runs as root — which is also the only reason
  # the legacy role's 0700 directory (owned by the deploy user, not the container) ever
  # worked. root-owned here rather than reproducing that mismatch.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/actual-budget 0700 root root -"
  ];

  sops.secrets = {
    "compose-stacks/actual-budget/oidc/client_id" = {
      sopsFile = ../../data/actual-budget.yaml;
    };
    "compose-stacks/actual-budget/oidc/client_secret" = {
      sopsFile = ../../data/actual-budget.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split as every
    # other OIDC client on this host.
    "compose-stacks/actual-budget/oidc/client_secret_hash" = {
      sopsFile = ../../data/actual-budget.yaml;
    };
  };

  # The OIDC client id/secret are carried over unchanged from the legacy vault
  # (vault_backbone__authelia__oidc_actual_budget_*) rather than rotated — the Phase 0
  # secrets table marks rotation as optional, and Actual keys its users by the OIDC
  # claims rather than by client, so nothing in the imported data depends on either.
  sops.templates."compose-actual-budget.env".content = ''
    ACTUAL_OPENID_DISCOVERY_URL=https://auth.${config.domains.main}/.well-known/openid-configuration
    ACTUAL_OPENID_CLIENT_ID=${config.sops.placeholder."compose-stacks/actual-budget/oidc/client_id"}
    ACTUAL_OPENID_CLIENT_SECRET=${
      config.sops.placeholder."compose-stacks/actual-budget/oidc/client_secret"
    }
    ACTUAL_OPENID_SERVER_HOSTNAME=https://actual.${config.domains.main}
  '';

  # No Authelia forwardAuth middleware, matching the legacy router: Actual is an OIDC
  # relying party in its own right and ACTUAL_OPENID_ENFORCE disables its password
  # login, so the client's own authorization_policy (auth/authelia-configuration.nix)
  # is the gate. A forwardAuth on top would also break the sync API calls the desktop
  # and mobile clients make with no browser session.
  reverseProxy.dynamicConfig.actual-budget = ''
    http:
      routers:
        actual:
          rule: "Host(`actual.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: actual
          tls:
            certResolver: le_main
      services:
        actual:
          loadBalancer:
            servers:
              - url: "http://actual-budget:5006"
  '';

  compose-stacks.stacks.actual-budget = {
    restartTriggers = [
      ../../data/actual-budget.yaml
      config.sops.templates."compose-actual-budget.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-actual-budget.env".path;
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
