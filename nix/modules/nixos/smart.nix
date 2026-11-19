{ config, lib, ... }:
let
  cfg = config.smart;
in
{
  options.smart = {
    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Upstream disko's own option rather than any one layout's custom ones
      # (mainDiskPath, pools.*.disks, secondaryDisks, ...), so this works with every
      # layout in ./disko/layouts. It only lists the disks disko partitions, which is
      # what keeps the LUKS key USB sticks out: smartctl's own autodiscovery would pick
      # them up and report them as unsupported devices forever.
      default = lib.unique (lib.mapAttrsToList (_: d: d.device) (config.disko.devices.disk or { }));
      defaultText = lib.literalExpression "every config.disko.devices.disk.<name>.device";
      description = ''
        Disks to monitor (`/dev/disk/by-id/...` paths), both by the Prometheus
        smartctl exporter and by smartd's scheduled self-tests.
      '';
    };
    exporterPort = lib.mkOption {
      type = lib.types.port;
      default = 9633;
      description = "Loopback port of the smartctl exporter, scraped by Alloy (grafana-alloy.smartMetrics).";
    };
    selfTestSchedule = lib.mkOption {
      type = lib.types.str;
      # Short test daily at 02:00, long (full surface read) on the 15th at 03:00. The
      # long test takes about a day on the 16 TB disk. It runs on the 15th because
      # services.btrfs.autoScrub is `monthly`, which is the 1st at midnight, and the two
      # running at once would both crawl.
      default = "(S/../.././02|L/../15/./03)";
      description = "smartd `-s` regexp scheduling the self-tests (see `man 5 smartd.conf`).";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.devices != [ ];
        message = "smart: no disks to monitor. Set smart.devices (the default reads them from disko).";
      }
    ];

    # Exposes every SMART attribute in Prometheus format. Alerting is Prometheus's job
    # (apps-01's monitoring stack), so the exporter is the only SMART data source that
    # leaves the host.
    services.prometheus.exporters.smartctl = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.exporterPort;
      devices = cfg.devices;
      # How often a disk may actually be queried, whatever the scrape rate. SMART data
      # moves on the scale of hours.
      maxInterval = "5m";
    };

    # smartd only runs the self-tests here: the exporter can read their results but
    # cannot start them. Its own notifications are off (no MTA on these hosts anyway),
    # because a failed test already shows up in the exporter's metrics and alerts from
    # there.
    services.smartd = {
      enable = true;
      autodetect = false;
      devices = map (device: { inherit device; }) cfg.devices;
      # -a: monitor everything; -o on: automatic offline data collection; -S on:
      # attribute autosave; -s: the self-test schedule.
      defaults.monitored = "-a -o on -S on -s ${cfg.selfTestSchedule}";
      notifications = {
        mail.enable = false;
        wall.enable = false;
        x11.enable = false;
      };
    };
  };
}
