{ config, lib, ... }:
let
  cfg = config.grafana-alloy;
in
{
  options.grafana-alloy = {
    hostname = lib.mkOption {
      default = config.system.name;
    };
    varlogs.enable = lib.mkEnableOption "/var/log collection";
    journald.enable = lib.mkEnableOption "journald (systemd) collection";
    containerlogs.enable = lib.mkEnableOption "Docker logs collection" // {
      description = ''
        Collect Docker container logs, labelled `job="containerlogs"` with
        `compose_project`, `compose_service`, `container_id` and `stream` — the same
        schema the legacy Ansible pipeline produces, so one Grafana dashboard covers
        both.

        Implemented on top of the journald collector rather than by tailing
        `/var/lib/docker/containers`, because Docker here uses the journald log driver.
        Enabling this also configures Docker to attach the compose labels as journal
        fields, and lifts systemd's log rate limit on `docker.service` (every container
        shares that unit's single rate-limit bucket, so one chatty container would
        otherwise suppress all of them).

        Requires `journald.enable`, `virtualisation.docker.enable`, and the journald log
        driver; all three are asserted.
      '';
    };
    nodeMetrics.enable = lib.mkEnableOption "host metrics collection (embedded node_exporter)";
    cadvisorMetrics.enable = lib.mkEnableOption "container metrics collection (embedded cAdvisor)";
    loki.endpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://loki.snyssen.be/loki/api/v1/push" ];
      description = "Loki push endpoints. One per destination stack to dual-ship to.";
    };
    remoteWrite.endpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Prometheus remote_write endpoints. Empty disables metrics shipping.";
    };
  };

  config =
    let
      alloy_varlogs = ''
        local.file_match "varlogs" {
          path_targets = [{
            __address__ = "localhost",
            __path__    = "/var/log/**/*log",
            host        = "${cfg.hostname}",
            job         = "varlogs",
          }]
        }

        loki.source.file "varlogs" {
          targets               = local.file_match.varlogs.targets
          forward_to            = [loki.write.default.receiver]
        }
      '';
      # Container logs are read out of the journal, not out of
      # /var/lib/docker/containers/*/*log: NixOS defaults
      # virtualisation.docker.logDriver to "journald", so those files do not exist (and
      # Alloy, running as a DynamicUser, could not read them anyway — /var/lib/docker is
      # 0710 root:root). Docker's journald driver instead writes every container line
      # into the journal with CONTAINER_ID/CONTAINER_NAME fields, plus whatever labels
      # log-opts.labels-regex selects (set below).
      #
      # These rules re-label those entries to the schema the legacy Ansible pipeline
      # produces from the json-file driver — job="containerlogs" with compose_project /
      # compose_service / container_id — so the same Grafana dashboards work against both
      # the legacy box and this one throughout the migration.
      #
      # Every rule is anchored on __journal_container_id, which only the journald log
      # driver sets. Prometheus relabelling anchors its regexes and treats a non-matching
      # `replace` as a no-op, so sshd/kernel/dockerd's own messages fall through
      # untouched and stay job="journald". That is also why hosts without
      # containerlogs.enable are completely unaffected.
      #
      # Entries are re-labelled, not duplicated: one source, one forward_to. There is
      # nothing to "drop" from the journald job, because a container line simply stops
      # being part of it.
      alloy_containerlogRules = ''
        rule {
          source_labels = ["__journal_container_id"]
          regex         = ".+"
          target_label  = "job"
          replacement   = "containerlogs"
        }
        rule {
          source_labels = ["__journal_container_id"]
          regex         = "(.+)"
          target_label  = "container_id"
        }
        rule {
          source_labels = ["__journal_com_docker_compose_project"]
          regex         = "(.+)"
          target_label  = "compose_project"
        }
        rule {
          source_labels = ["__journal_com_docker_compose_service"]
          regex         = "(.+)"
          target_label  = "compose_service"
        }
        // Docker's journald driver has no "stream" field; it sends stderr at PRIORITY 3
        // and stdout at 6. Pairing the priority with container_id is deliberate —
        // matching on priority alone would put a `stream` label on every ordinary
        // journal entry and split the existing job="journald" streams by severity.
        rule {
          source_labels = ["__journal_container_id", "__journal_priority"]
          separator     = ";"
          regex         = ".+;6"
          target_label  = "stream"
          replacement   = "stdout"
        }
        rule {
          source_labels = ["__journal_container_id", "__journal_priority"]
          separator     = ";"
          regex         = ".+;3"
          target_label  = "stream"
          replacement   = "stderr"
        }
      '';
      alloy_journald = ''
        loki.relabel "journald" {
          forward_to = []
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }
          ${lib.optionalString cfg.containerlogs.enable alloy_containerlogRules}
        }

        loki.source.journal "journald"  {
          forward_to    = [loki.write.default.receiver]
          relabel_rules = loki.relabel.journald.rules
          labels        = {
            component = "journald",
            job       = "journald",
            host      = "${cfg.hostname}",
          }
        }
      '';
      alloy_nodeMetrics = ''
        prometheus.exporter.unix "default" { }

        prometheus.scrape "node" {
          targets         = prometheus.exporter.unix.default.targets
          forward_to      = [prometheus.relabel.node.receiver]
          // Alloy's default is 60s. The legacy Prometheus (and every other host's
          // node/cadvisor scrape job there) uses 15s — rate()/irate() queries over a
          // short window (dashboards commonly hardcode [1m], or Grafana computes
          // $__rate_interval from the datasource's configured 15s scrape interval)
          // need at least 2 samples inside that window; at 60s spacing they often
          // don't get one, silently producing "No data" for every panel doing a rate
          // calculation while plain gauge-value panels (memory, filesystems) still
          // work fine. Matching the fleet's cadence fixes this and keeps resolution
          // consistent with every pull-scraped host.
          scrape_interval = "15s"
        }

        // prometheus.scrape's job_name only fills in a job label if the target
        // doesn't already carry one — prometheus.exporter.unix's targets already set
        // job="integrations/unix" themselves, so job_name is silently ignored
        // (confirmed the hard way: job_name = "node" on the scrape block above built
        // and deployed fine but had no effect). An explicit relabel rule after the
        // scrape is what actually overwrites it, matching the job name every existing
        // dashboard/alert (legacy and new) is built around, same as a plain
        // Prometheus scrape_configs job_name would produce.
        prometheus.relabel "node" {
          forward_to = [prometheus.remote_write.default.receiver]
          rule {
            action       = "replace"
            target_label = "job"
            replacement  = "node"
          }
        }
      '';
      alloy_cadvisorMetrics = ''
        prometheus.exporter.cadvisor "default" {
          docker_host = "unix:///var/run/docker.sock"
          // NixOS's docker module runs Docker's own embedded containerd, not a
          // standalone one — cadvisor's containerd_host default
          // (/run/containerd/containerd.sock) doesn't exist here, and the real one
          // (/run/docker/containerd/containerd.sock) is root-only by design (dockerd's
          // own private socket, not meant for external clients), not something
          // SupplementaryGroups can grant access to. docker_only skips the
          // containerd-dependent discovery path entirely, relying only on the Docker
          // API (docker_host above) instead — everything on this host is Docker
          // Compose-managed anyway, so nothing is lost.
          docker_only = true
        }

        prometheus.scrape "cadvisor" {
          targets         = prometheus.exporter.cadvisor.default.targets
          forward_to      = [prometheus.relabel.cadvisor.receiver]
          // See the comment on prometheus.scrape "node" above.
          scrape_interval = "15s"
        }

        // See the comment on prometheus.relabel "node" above — same reason this is
        // needed instead of prometheus.scrape's own job_name.
        prometheus.relabel "cadvisor" {
          forward_to = [prometheus.remote_write.default.receiver]
          rule {
            action       = "replace"
            target_label = "job"
            replacement  = "cadvisor"
          }
        }
      '';
      alloy_remoteWrite = ''
        prometheus.remote_write "default" {
          ${lib.concatMapStrings (url: ''
            endpoint {
              url = "${url}"
            }
          '') cfg.remoteWrite.endpoints}
        }
      '';
      alloy_loki = ''
        loki.write "default" {
          ${lib.concatMapStrings (url: ''
            endpoint {
              url = "${url}"
            }
          '') cfg.loki.endpoints}
          external_labels = {}
        }
      '';
    in
    {
      services.alloy = {
        enable = true;
        extraFlags = [ "--disable-reporting" ];
      };

      # Traefik group: read access to its log files. Docker group: cadvisorMetrics
      # needs /var/run/docker.sock. Computed as one list rather than two separate
      # mkIf blocks, since NixOS's merge behavior for serviceConfig.SupplementaryGroups
      # contributions across multiple module definitions isn't something to rely on
      # here — this is the only place either group gets added.
      systemd.services.alloy.serviceConfig =
        lib.mkIf (config.services.traefik.enable || cfg.cadvisorMetrics.enable)
          {
            SupplementaryGroups =
              lib.optional config.services.traefik.enable "traefik"
              ++ lib.optional cfg.cadvisorMetrics.enable "docker";
          };

      # Make Docker attach the two compose labels to every journal entry, which is what
      # the containerlog relabel rules above turn into compose_project/compose_service.
      #
      # Deliberately narrower than the legacy box's `^.+`: with the json-file driver
      # that produces one `attrs` object per line, parsed once and mostly discarded,
      # whereas here every matched label becomes a journal field *stored on every
      # entry*. These containers carry a lot of long Traefik labels, and Traefik's own
      # access log is the chattiest stream on the host. Docker also uppercases label
      # names and maps non-alphanumerics to `_`, so a wide regex can collide unrelated
      # labels into one field.
      #
      # Note the journald driver rejects the json-file driver's max-size/max-file —
      # journald does its own rotation.
      virtualisation.docker.daemon.settings = lib.mkIf cfg.containerlogs.enable {
        log-opts.labels-regex = "^com\\.docker\\.compose\\.(project|service)$";
      };

      # Every container logs through dockerd, so they all share this unit's single
      # rate-limit bucket (stock: 10000 messages / 30s). Without this, one noisy
      # container silently suppresses every other container's logs. Per-unit, so the
      # global limit still applies to everything else.
      systemd.services.docker.serviceConfig = lib.mkIf cfg.containerlogs.enable {
        LogRateLimitIntervalSec = 0;
      };

      # Each of these would otherwise fail silently — producing no containerlogs job at
      # all, which is exactly how the original file-based implementation went unnoticed.
      assertions = [
        {
          assertion = cfg.containerlogs.enable -> config.virtualisation.docker.enable;
          message = "grafana-alloy.containerlogs.enable requires virtualisation.docker.enable.";
        }
        {
          # The enum option, not daemon.settings.log-driver, which this module writes.
          assertion = cfg.containerlogs.enable -> config.virtualisation.docker.logDriver == "journald";
          message = ''
            grafana-alloy.containerlogs.enable reads container output out of the journal,
            so Docker must use the journald log driver
            (virtualisation.docker.logDriver = "journald", the NixOS default).
          '';
        }
        {
          assertion = cfg.containerlogs.enable -> cfg.journald.enable;
          message = "grafana-alloy.containerlogs.enable is implemented on top of grafana-alloy.journald.enable.";
        }
      ];

      environment.etc."alloy/config.alloy".text = ''
        ${if cfg.varlogs.enable then alloy_varlogs else ""}
        ${if cfg.journald.enable then alloy_journald else ""}
        ${if cfg.nodeMetrics.enable then alloy_nodeMetrics else ""}
        ${if cfg.cadvisorMetrics.enable then alloy_cadvisorMetrics else ""}
        ${if cfg.remoteWrite.endpoints != [ ] then alloy_remoteWrite else ""}
        ${alloy_loki}
      '';
    };
}
