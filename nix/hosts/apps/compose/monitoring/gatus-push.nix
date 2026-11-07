{ config, pkgs }:
# `gatus-push <key> <true|false>`: report a job's result to one of Gatus's external
# endpoints (see gatus-config.nix), for jobs that prove they ran by pushing rather than
# being polled. Shared by every such job on this host: the nextcloud cron timer and
# Backrest's backup hooks.
#
# The key is Gatus's `<group>_<name>`, lowercased with spaces turned into dashes. It
# goes to the allowlisted `uptime-push` route (see default.nix), not the Authelia-gated
# one. The token is sent from stdin (`-H @-`) so it never appears in a process list.
# -f makes a rejected push fail loudly: a 401/403 here means the token or the allowlist
# is wrong, and the endpoint would otherwise go red with no clue why.
pkgs.writeShellScript "gatus-push" ''
  set -euo pipefail
  printf 'Authorization: Bearer %s\n' "$(cat ${
    config.sops.secrets."compose-stacks/monitoring/gatus/push_token".path
  })" | ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 -o /dev/null -H @- -X POST \
    "https://uptime.${config.domains.main}/api/v1/endpoints/$1/external?success=$2"
''
