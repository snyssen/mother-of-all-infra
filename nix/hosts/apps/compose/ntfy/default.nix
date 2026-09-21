{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/ntfy/cache 0755 root root -"
    "d /var/lib/app-data/ntfy/auth 0755 root root -"
  ];

  sops.secrets = {
    "compose-stacks/ntfy/users/snyssen/password_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    "compose-stacks/ntfy/users/monitoring/password_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    "compose-stacks/ntfy/users/hass/password_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    "compose-stacks/ntfy/users/streaming/password_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    "compose-stacks/ntfy/users/streaming/token" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    # Used as the topic *name* itself (via NTFY_AUTH_ACCESS below), not just an opaque
    # value — an unguessable topic name is what actually keeps it private, same as the
    # legacy vault-backed setup relied on.
    "compose-stacks/ntfy/topics/monitoring" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
    "compose-stacks/ntfy/topics/hass" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-ntfy.service" ];
    };
  };

  # All four users/hashes/topic names are carried over unchanged from the legacy
  # Ansible Vault (ntfy__users/ntfy__topics__* in group_vars/apps/vars.yml) rather than
  # rotated — this migration's own Phase 0 secrets table marks ntfy rotation as
  # "Optional", and reusing them means every existing subscriber (phone UnifiedPush,
  # Home Assistant's notify platform, the *arr apps' webhook token, the monitoring
  # stack's alert channel) keeps working unchanged through cutover.
  sops.templates."compose-ntfy.env".content = ''
    NTFY_BASE_URL=https://ntfy.${config.domains.main}
    NTFY_AUTH_USERS=snyssen:${config.sops.placeholder."compose-stacks/ntfy/users/snyssen/password_hash"}:user,monitoring:${config.sops.placeholder."compose-stacks/ntfy/users/monitoring/password_hash"}:user,hass:${config.sops.placeholder."compose-stacks/ntfy/users/hass/password_hash"}:user,streaming:${config.sops.placeholder."compose-stacks/ntfy/users/streaming/password_hash"}:user
    NTFY_AUTH_ACCESS=*:up*:wo,snyssen:*:ro,monitoring:${config.sops.placeholder."compose-stacks/ntfy/topics/monitoring"}:rw,hass:${config.sops.placeholder."compose-stacks/ntfy/topics/hass"}:rw,streaming:streaming:rw
    NTFY_AUTH_TOKENS=streaming:${config.sops.placeholder."compose-stacks/ntfy/users/streaming/token"}
  '';

  # No Authelia/crowdsec-waf gating — ntfy enforces its own per-topic auth (see
  # NTFY_AUTH_* above), matching the legacy setup which had no `authelia@docker`
  # middleware on this router either.
  reverseProxy.dynamicConfig.ntfy = ''
    http:
      routers:
        ntfy:
          rule: "Host(`ntfy.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: ntfy
          tls:
            certResolver: le_main
      services:
        ntfy:
          loadBalancer:
            servers:
              - url: "http://ntfy:80"
  '';

  compose-stacks.stacks.ntfy = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-ntfy.env".path;
    dockerNetworks = [
      "web"
      "monitoring"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
