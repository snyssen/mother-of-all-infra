{ pkgs, ... }:
# Offline checks for apps-01's alerting (nix/hosts/apps-01/compose/monitoring):
# Prometheus rules syntax, the alert rules' unit tests, and the Alertmanager config.
let
  monitoring = ../hosts/apps-01/compose/monitoring;
in
pkgs.runCommand "monitoring-check"
  {
    nativeBuildInputs = [
      pkgs.prometheus.cli # promtool
      pkgs.prometheus-alertmanager # amtool
    ];
  }
  ''
    cd ${monitoring}
    promtool check rules prometheus/rules/*.yml
    promtool test rules prometheus/tests/*.test.yml
    amtool check-config alertmanager.yml
    touch $out
  ''
