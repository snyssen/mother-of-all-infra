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
    loki.endpoint = lib.mkOption {
      default = "https://loki.snyssen.be/loki/api/v1/push";
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
      alloy_loki = ''
        loki.write "default" {
        	endpoint {
        		url = "${cfg.loki.endpoint}"
        	}
        	external_labels = {}
        }
      '';
    in
    {
      services.alloy = {
        enable = true;
        extraFlags = [ "--disable-reporting" ];
      };

      systemd.services.alloy.serviceConfig = lib.mkIf config.services.traefik.enable {
        SupplementaryGroups = [ "traefik" ];
      };

      environment.etc."alloy/config.alloy".text = ''
        ${if cfg.varlogs.enable then alloy_varlogs else ""}
        ${if cfg.journald.enable then alloy_journald else ""}
        ${if cfg.containerlogs.enable then alloy_containerlogs else ""}
        ${alloy_loki}
      '';
    };
}
