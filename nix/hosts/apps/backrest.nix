{ config, ... }:
{
  # Restore-testing bridge only (see docs/backups.md and the migration plan's Backups
  # row): registers the existing production on-site REST-server repo so Backrest's UI
  # can browse and restore *any* of autorestic's existing snapshots onto `apps`,
  # retargeted to arbitrary paths — no backup plan needed for that, Backrest indexes a
  # repo's snapshots directly regardless of what created them. `apps`'s own backup
  # plans (and its own off-site B2 repo) are a separate, later, incremental piece of
  # work once there's real data on `apps` worth protecting.
  sops.secrets."backrest/repos/backup_snyssen_be/password" = {
    sopsFile = ./data/secrets.yaml;
    restartUnits = [ "backrest.service" ];
  };
  sops.secrets."backrest/users/snyssen/password_hash" = {
    sopsFile = ./data/secrets.yaml;
    restartUnits = [ "backrest.service" ];
  };

  backrest = {
    enable = true;
    # Direct access without going through Traefik/Authelia — safe to open now that
    # the UI has its own real login (see users below). Only reachable from the
    # tailnet/LAN anyway, never the open WAN (apps has no public-facing interface of
    # its own; see the migration plan).
    openFirewall = true;
    repos.backup_snyssen_be = {
      # On-site dedicated restic REST server — LAN-only, no auth. Chosen over the
      # off-site B2 repo (snyssen-be-autorestic) specifically for restore-testing:
      # LAN speed between it and `apps`, and it's the richer/more complete repo (every
      # autorestic location writes here; only some also go to B2).
      uri = "rest:http://backup.snyssen.be:8000/";
      passwordSecret = "backrest/repos/backup_snyssen_be/password"; # Uses sops templates behind the scene
      # Fixed/stable, not a secret — just needs to stay constant across redeploys.
      # Generated once with `openssl rand -hex 32`.
      guid = "6498b158e271405733d31947e066cf746e6a6a5b07206075cdb55763f09fb9db";
    };
    users.snyssen.passwordHashSecret = "backrest/users/snyssen/password_hash";
  };

  # Defense in depth: Authelia gates this route same as every other admin UI here, on
  # top of Backrest's own login (declared above) — the latter alone is also what
  # protects the direct/firewall-opened path, which bypasses Authelia entirely.
  reverseProxy.dynamicConfig.backrest = ''
    http:
      routers:
        backrest:
          rule: "Host(`backrest.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: backrest
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        backrest:
          loadBalancer:
            servers:
              - url: "http://host.docker.internal:9898"
  '';
}
