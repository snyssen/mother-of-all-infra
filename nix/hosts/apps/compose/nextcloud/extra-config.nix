{ config }:
# Kept in its own file for the same reason as databases/pgadmin-config-local.nix and
# auth/authelia-configuration.nix: ordinary Nix interpolation for the sops placeholders
# and domain-derived URLs, without cluttering default.nix.
#
# Nextcloud loads every *.config.php in its config directory alphabetically, after
# config.php — so everything here overrides whatever the restored prod config.php says.
# That is what makes a prod import work at all: config.php comes back from the snapshot
# still pointing at prod's database password, prod's domain and prod's Redis host, and
# this file corrects all three without editing the restored file.
#
# Mirrors the legacy role's extra.config.php. Three deliberate differences from it,
# each marked below: the Redis host, the mail domain, and the logging target.
''
  <?php
  $CONFIG = array (
    'passwordsalt' => '${config.sops.placeholder."compose-stacks/nextcloud/passwordsalt"}',
    // NOTE THE TRAILING SPACE INSIDE THE QUOTES. It is in the legacy template too
    // ('{{ nextcloud__secret }} '), so prod's effective secret includes it, and this
    // value is what Nextcloud derives the key for every encrypted field from — app
    // passwords, external storage credentials, and anything the encryption app has
    // touched. Dropping the space would silently make all of that undecryptable after
    // the import. Reproduced verbatim rather than "cleaned up"; if you ever want it
    // gone, that is a deliberate re-key, not a whitespace fix.
    'secret' => '${config.sops.placeholder."compose-stacks/nextcloud/secret"} ',
    'trusted_domains' =>
    array(
      0 => 'localhost',
      1 => 'cloud.${config.domains.main}',
    ),
    // Which upstream addresses are allowed to set X-Forwarded-For. The legacy value is
    // a single /24 (172.18.0.0/24) because that is the subnet Docker happened to assign
    // prod's `web` network. Nothing pins that here — docker.networks creates these with
    // `docker network create --driver bridge` and no --subnet, so the assignment
    // depends on creation order and would silently stop matching. Widened to Docker's
    // whole default pool instead; every address in it is a container on this host.
    // Verify with `docker network inspect web` if client IPs ever look wrong in the
    // security log.
    'trusted_proxies' =>
    array(
      0 => '172.16.0.0/12',
    ),
    'overwrite.cli.url' => 'https://cloud.${config.domains.main}',
    'instanceid' => '${config.sops.placeholder."compose-stacks/nextcloud/instanceid"}',
    'memcache.distributed' => '\\OC\\Memcache\\Redis',
    'memcache.locking' => '\\OC\\Memcache\\Redis',
    'redis' =>
    // The empty PHP strings below and in the db block are written as three single
    // quotes rather than two. Inside a Nix indented string a doubled single-quote is
    // the closing delimiter, so writing the empty string literally ends the string
    // early and fails the build; tripling it is the escape for a literal pair.
    array(
      // `redis`, not the legacy `nextcloud_redis`: the sidecar is renamed in this
      // stack's compose file (see the comment there), and the restored config.php
      // still names the old one, so this override is load-bearing rather than
      // cosmetic — without it Nextcloud cannot reach its cache or take file locks.
      'host' => 'redis',
      'password' => ''',
      'port' => 6379,
    ),
    'dbtype' => 'pgsql',
    'dbname' => 'nextcloud',
    'dbhost' => 'postgres',
    'dbport' => ''',
    'dbtableprefix' => ''',
    'dbuser' => 'nextcloud',
    'dbpassword' => '${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/nextcloud"
    }',
    // Logging goes to the container's stderr instead of the legacy
    // /var/logs/nextcloud.log + audit.log pair, which existed only to give the
    // promtail sidecar something to tail. `errorlog` hands the lines to PHP's
    // error_log(); this image runs mod_php, whose SAPI logger is Apache's ErrorLog,
    // which the image symlinks to /dev/stderr. Docker's journald log driver puts that
    // into the systemd journal, where grafana-alloy's containerlogs collector picks it
    // up and labels it with compose_project/compose_service — see
    // nix/modules/nixos/grafana-alloy.nix.
    'log_type' => 'errorlog',
    'log_type_audit' => 'errorlog',
    'mail_smtpmode' => 'smtp',
    'mail_smtpsecure' => 'tls',
    'mail_sendmailmode' => 'smtp',
    'mail_from_address' => 'nextcloud',
    // The legacy template uses main_domain here. On this host that is snyssen1.xyz,
    // a throwaway name the relay has no SPF/DKIM for, so mail would be sent as
    // nextcloud@snyssen1.xyz and dropped. Uses the real sending domain instead, the
    // same way Authelia's sender address does.
    'mail_domain' => '${config.sops.placeholder."smtp/from_domain"}',
    'mail_smtpauthtype' => 'LOGIN',
    'mail_smtpauth' => 1,
    'mail_smtphost' => '${config.sops.placeholder."smtp/host"}',
    'mail_smtpport' => '${config.sops.placeholder."smtp/port"}',
    'mail_smtpname' => '${config.sops.placeholder."smtp/user"}',
    'mail_smtppassword' => '${config.sops.placeholder."smtp/password"}',
  );
''
