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
    containerlogs.enable = lib.mkEnableOption "Docker logs collection";
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
      alloy_journald = ''
        loki.relabel "journald" {
          forward_to = []
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }
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
      alloy_containerlogs = ''
        local.file_match "containerlogs" {
          path_targets = [{
            __address__ = "localhost",
            __path__    = "/var/lib/docker/containers/*/*log",
            host        = "${cfg.hostname}",
            job         = "containerlogs",
          }]
        }

        loki.process "containerlogs" {
          forward_to = [loki.write.default.receiver]

          stage.json {
            expressions = {
              compose_project    = "attrs.\"com.docker.compose.project\"",
              compose_service    = "attrs.\"com.docker.compose.service\"",
              log                = "log",
              stack_name         = "attrs.\"com.docker.stack.namespace\"",
              stream             = "stream",
              swarm_service_name = "attrs.\"com.docker.swarm.service.name\"",
              swarm_task_name    = "attrs.\"com.docker.swarm.task.name\"",
              tag                = "attrs.tag",
              time               = "time",
            }
          }

          stage.regex {
            expression = "^/var/lib/docker/containers/(?P<container_id>.{12}).+/.+-json.log$"
            source     = "filename"
          }

          stage.timestamp {
            source = "time"
            format = "RFC3339Nano"
          }

          stage.labels {
            values = {
              compose_project    = null,
              compose_service    = null,
              container_id       = null,
              stack_name         = null,
              stream             = null,
              swarm_service_name = null,
              swarm_task_name    = null,
              tag                = null,
            }
          }

          stage.output {
            source = "log"
          }
        }

        loki.source.file "containerlogs" {
          targets               = local.file_match.containerlogs.targets
          forward_to            = [loki.process.containerlogs.receiver]
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
      systemd.services.alloy.serviceConfig = lib.mkIf (
        config.services.traefik.enable || cfg.cadvisorMetrics.enable
      ) {
        SupplementaryGroups =
          lib.optional config.services.traefik.enable "traefik"
          ++ lib.optional cfg.cadvisorMetrics.enable "docker";
      };

      environment.etc."alloy/config.alloy".text = ''
        ${if cfg.varlogs.enable then alloy_varlogs else ""}
        ${if cfg.journald.enable then alloy_journald else ""}
        ${if cfg.containerlogs.enable then alloy_containerlogs else ""}
        ${if cfg.nodeMetrics.enable then alloy_nodeMetrics else ""}
        ${if cfg.cadvisorMetrics.enable then alloy_cadvisorMetrics else ""}
        ${if cfg.remoteWrite.endpoints != [ ] then alloy_remoteWrite else ""}
        ${alloy_loki}
      '';
    };
}
