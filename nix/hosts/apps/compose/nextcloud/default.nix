{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";

in
{
  sops.secrets = {
    # Carried over from the legacy vault unchanged, and all three have to be: they are
    # what the restored data is keyed to. `instanceid` names the instance's own
    # appdata_<id> directory inside the data tree, `passwordsalt` and `secret` derive
    # the keys for every encrypted field. A fresh value for any of them turns an
    # imported library into an instance that boots but cannot read its own secrets.
    "compose-stacks/nextcloud/passwordsalt" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/secret" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/instanceid" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/admin/user" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/admin/password" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    # Uptime Kuma push monitor for the cron timer below. Not a credential as such —
    # it is the capability itself, which is why it goes through an allowlisted route
    # rather than an authenticated one. It comes back with the restored Uptime Kuma
    # data, so read it off the "nextcloud background job" monitor there.
    "compose-stacks/nextcloud/uptime_push_token" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/oidc/client_id" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    "compose-stacks/nextcloud/oidc/client_secret" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split already used
    # for Grafana/CrowdSec/PeerTube/pgAdmin/Immich/Paperless's OIDC clients. The OIDC
    # app's own copy of the client id/secret lives in Nextcloud's database and comes
    # back with the import, so the plaintext pair above exists to keep that
    # reconfigurable, not because the container reads it at boot.
    "compose-stacks/nextcloud/oidc/client_secret_hash" = {
      sopsFile = ../../data/nextcloud.yaml;
    };
  };

  # The database password is deliberately not a nextcloud-owned secret: the role lives
  # in the central `databases` cluster, which provisions it from its own
  # PG_PASSWORD_NEXTCLOUD. The restored config.php still carries prod's password, which
  # is why extra-config.nix overrides dbpassword rather than leaving it alone.
  sops.templates."compose-nextcloud.env".content = ''
    NEXTCLOUD_DB_PASSWORD=${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/nextcloud"
    }
    NEXTCLOUD_ADMIN_USER=${config.sops.placeholder."compose-stacks/nextcloud/admin/user"}
    NEXTCLOUD_ADMIN_PASSWORD=${config.sops.placeholder."compose-stacks/nextcloud/admin/password"}
    NEXTCLOUD_TRUSTED_DOMAINS=cloud.${config.domains.main}
  '';

  # See extra-config.nix for why this lives in its own file and what it overrides.
  # Rendered to /run/secrets/rendered/ as root-only; nextcloud-config.service below is
  # what puts a readable copy where the container can actually see it.
  sops.templates."nextcloud-extra.config.php" = {
    content = import ./extra-config.nix { inherit config; };
  };

  # No authelia middleware: Nextcloud is the OIDC relying party itself (via its
  # user_oidc app, configured in its own database), same pattern as
  # Grafana/PeerTube/pgAdmin/Immich elsewhere in this migration. Its clients — desktop
  # sync, mobile, CalDAV/CardDAV — have no browser session to offer a forwardAuth gate
  # anyway, so putting one in front would break far more than it protected.
  #
  # Both middlewares are carried over from the legacy Traefik labels. The redirect is
  # not cosmetic: CalDAV/CardDAV clients discover the server by requesting
  # /.well-known/carddav, and without the rewrite to /remote.php/dav/ they fail to
  # configure at all.
  reverseProxy.dynamicConfig.nextcloud = ''
    http:
      routers:
        nextcloud:
          rule: "Host(`cloud.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: nextcloud
          middlewares:
            - nextcloud-headers
            - nextcloud-redirect
          tls:
            certResolver: le_main
      services:
        nextcloud:
          loadBalancer:
            servers:
              - url: "http://nextcloud:80"
      middlewares:
        nextcloud-headers:
          headers:
            customFrameOptionsValue: SAMEORIGIN
            contentSecurityPolicy: "frame-ancestors 'self' cloud.${config.domains.main}"
            stsSeconds: 155520011
            stsIncludeSubdomains: true
            stsPreload: true
        nextcloud-redirect:
          redirectRegex:
            regex: "/.well-known/(card|cal)dav"
            replacement: "/remote.php/dav/"
  '';

  compose-stacks.stacks.nextcloud = {
    restartTriggers = [
      ../../data/nextcloud.yaml
      ../../data/databases.yaml
      ../../data/common.yaml
      config.sops.templates."compose-nextcloud.env".content
      config.sops.templates."nextcloud-extra.config.php".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-nextcloud.env".path;
    dockerNetworks = [
      "web"
      "db"
      "ldap"
    ];
    # Dormant until the data is actually here, the same way the streaming stack is.
    #
    # This is not caution for its own sake: Nextcloud's database and its file tree are
    # a matched pair. Started against an empty /mnt/bulk/nextcloud, the entrypoint runs
    # its first-run installer, writes a fresh config.php and version.php and populates
    # the database — and a later `postgres-restore nextcloud` then drops that in favour
    # of prod's schema while the freshly-installed files stay behind. Import both
    # halves first (`prod-import nextcloud` + `postgres-restore nextcloud`), then flip
    # this to true.
    autostart = false;
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "nextcloud-config.service"
    ];
  };

  # Same shape as the other stacks' storage-dirs units: /mnt/bulk subpaths can't go
  # through ordinary tmpfiles rules, which run before the NFS mount is up. 33:33 is the
  # container's www-data, matching both the legacy role's file task and the ownership
  # the restored snapshot carries.
  systemd.services.nextcloud-storage-dirs = {
    description = "Create /mnt/bulk directories the nextcloud stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "nextcloud-config.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nextcloud-storage-dirs" ''
        set -euo pipefail
        install -d -m 0750 -o 33 -g 33 \
          /mnt/bulk/nextcloud \
          /mnt/bulk/nextcloud/config
      '';
    };
  };

  # Installs the rendered extra.config.php into the config directory, which is where
  # the legacy Ansible role put it too (owner 33, group 33).
  #
  # Copied rather than bind-mounted straight from /run/secrets/rendered: the container
  # reads this file as www-data, so a bind mount would mean making the rendered secret
  # world-readable on the host — and it holds `secret`, `passwordsalt` and two
  # passwords. Landing it at 0640 owned by uid 33 keeps it no more exposed than the
  # config.php sitting beside it, which carries the same values anyway.
  #
  # `install` writes to a temporary file and renames, so a half-written config is never
  # visible to a running Nextcloud.
  systemd.services.nextcloud-config = {
    description = "Install extra.config.php for the nextcloud stack";
    # Same triggers as the stack itself: this unit has to reinstall the file whenever
    # either the template's text or any secret it renders changes. It is always active
    # (RemainAfterExit), so a trigger always reaches it.
    restartTriggers = [
      ../../data/nextcloud.yaml
      ../../data/databases.yaml
      ../../data/common.yaml
      config.sops.templates."nextcloud-extra.config.php".content
    ];
    after = [ "nextcloud-storage-dirs.service" ];
    requires = [ "nextcloud-storage-dirs.service" ];
    before = [ "compose-nextcloud.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nextcloud-config" ''
        set -euo pipefail
        install -m 0640 -o 33 -g 33 \
          ${config.sops.templates."nextcloud-extra.config.php".path} \
          /mnt/bulk/nextcloud/config/extra.config.php
      '';
    };
  };

  # Replaces the legacy role's `*/5 * * * * docker exec -u www-data nextcloud php
  # cron.php` root crontab entry. Nextcloud degrades quietly without this — file scans,
  # notifications, trash/version expiry and federated retries all ride on it.
  #
  # The push to Uptime Kuma afterwards is the legacy entry's second half, and it is
  # what detects the failure mode systemd cannot report on its own: a timer that stops
  # firing at all. It reaches the allowlisted uptime-push route (see
  # compose/monitoring), not the Authelia-gated one.
  #
  # Written as a script rather than a second ExecStart= line so the token is read from
  # its secret file at runtime — an ExecStart would put it in the unit file, which is
  # world-readable in the Nix store.
  systemd.services.nextcloud-cron = {
    description = "Run Nextcloud's background job queue";
    after = [ "compose-nextcloud.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nextcloud-cron" ''
        set -euo pipefail
        ${pkgs.docker}/bin/docker compose --project-name nextcloud -f ${composeFile} \
          exec -T -u www-data nextcloud php cron.php
        # Only reached if cron.php succeeded, matching the legacy `&&`. -f makes a
        # rejected push fail the unit loudly: if the allowlist ever stops matching
        # this host, Traefik answers 403 and this exits non-zero rather than quietly
        # reporting success while the monitor goes red on its own.
        ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 -o /dev/null \
          "https://uptime.${config.domains.main}/api/push/$(cat ${
            config.sops.secrets."compose-stacks/nextcloud/uptime_push_token".path
          })?status=up&msg=OK&ping="
      '';
    };
  };

  systemd.timers.nextcloud-cron = {
    description = "Nextcloud background job queue, every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      # Nextcloud itself tracks how overdue each job is, so a catch-up run after
      # downtime is wanted here — unlike the paperless export, where it would mean a
      # full re-export at boot.
      Persistent = true;
    };
  };
}
