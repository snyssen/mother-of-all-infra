{ pkgs, ... }:
# Offline check for apps-01's ntfy message template for Alertmanager
# (nix/hosts/apps-01/compose/ntfy/alertmanager-template.nix). ntfy rejects a publish whose
# template it refuses or whose rendered message is too large, and Alertmanager does not
# retry a 400, so such an alert is silently lost: this renders it the way prod does.
#
# Two parts, as nixpkgs' ntfy lags the pinned image (compose/ntfy/docker-compose.yaml):
# - a real ntfy server renders realistic payloads, which catches syntax, rendering and
#   size errors (the 4 KB default message limit);
# - a scan for the builtins ntfy refuses since v2.38, which the nixpkgs one may not yet
#   do. Keep `disallowed` in step with `templateDisallowedFuncs` in ntfy's
#   server/server_template.go when bumping ntfy.
let
  inherit (pkgs) lib;

  templates = pkgs.writeTextDir "alertmanager-grafana.yml" (
    import ../hosts/apps-01/compose/ntfy/alertmanager-template.nix {
      grafanaUrl = "https://monitor.example.org";
    }
  );

  disallowed = [
    "call"
    "html"
    "js"
    "urlquery"
    "define"
    "template"
    "block"
  ];

  # Alertmanager webhook payloads (only the fields the template reads, plus a few for
  # realism).
  payload =
    status: alerts:
    let
      commonLabels = lib.filterAttrs (n: v: lib.all (a: a.labels.${n} or null == v) alerts) (
        (builtins.head alerts).labels
      );
      commonAnnotations = lib.filterAttrs (n: v: lib.all (a: a.annotations.${n} or null == v) alerts) (
        (builtins.head alerts).annotations
      );
    in
    builtins.toJSON {
      version = "4";
      receiver = "ntfy";
      inherit status commonLabels commonAnnotations;
      groupLabels = { inherit (commonLabels) alertname; };
      externalURL = "http://alertmanager:9093";
      alerts = map (a: a // { status = a.status or status; }) alerts;
    };

  endpointDown = name: {
    labels = {
      alertname = "EndpointDown";
      group = "backups";
      inherit name;
      priority = "default";
      severity = "error";
    };
    annotations = {
      summary = "backups/${name} is failing its Gatus check";
      dashboard_uid = "CN8E-vZ7k1";
    };
  };

  targetDown = {
    labels = {
      alertname = "TargetDown";
      instance = "backup.example.org:8000";
      job = "rest_server";
      priority = "default";
      severity = "warning";
      # Every character the silence matchers have to percent-encode.
      odd = ''a b&c#d+e%f"g=h'';
    };
    annotations = {
      summary = "rest_server target backup.example.org:8000 is down";
      description = "Prometheus cannot scrape it.";
    };
  };

  # name -> { payload; expect: a fixed string the rendered message must contain }
  cases = {
    single-firing = {
      payload = payload "firing" [ targetDown ];
      expect = "&matcher=odd%3Da%20b%26c%23d%2Be%25f%22g%3Dh";
    };
    single-resolved = {
      payload = payload "resolved" [ targetDown ];
      expect = "✅ rest_server target";
    };
    # Every backup check failing at once: one group, as EndpointDown has no `instance`.
    many-firing = {
      payload = payload "firing" (map (i: endpointDown "backup-${toString i}") (lib.range 1 60));
      expect = "(all 60)";
    };
  };
in
pkgs.runCommand "ntfy-template-check"
  {
    nativeBuildInputs = [
      pkgs.unstable.ntfy-sh
      pkgs.curl
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    tpl=${templates}/alertmanager-grafana.yml

    # Builtins ntfy refuses, anywhere inside an action.
    if grep -oP '\{\{.*?\}\}' "$tpl" | grep -wE '${lib.concatStringsSep "|" disallowed}'; then
      echo "ntfy refuses these template builtins: ${toString disallowed}" >&2
      exit 1
    fi

    ntfy serve --config /dev/null --listen-http 127.0.0.1:2586 \
      --base-url http://127.0.0.1:2586 --template-dir ${templates} &
    for _ in $(seq 50); do
      curl -sf http://127.0.0.1:2586/v1/health >/dev/null && break
      sleep 0.2
    done

    ${lib.concatStrings (
      lib.mapAttrsToList (name: c: ''
        echo "== ${name}"
        code=$(curl -s -o resp.json -w '%{http_code}' \
          'http://127.0.0.1:2586/alerts?template=alertmanager-grafana&markdown=yes' \
          --data-binary @${pkgs.writeText "${name}.json" c.payload})
        cat resp.json; echo
        [ "$code" = 200 ] || { echo "ntfy answered $code" >&2; exit 1; }
        jq -er .message resp.json | grep -qF -- ${lib.escapeShellArg c.expect} \
          || { echo "message lacks: "${lib.escapeShellArg c.expect} >&2; exit 1; }
      '') cases
    )}

    kill %1
    touch $out
  ''
