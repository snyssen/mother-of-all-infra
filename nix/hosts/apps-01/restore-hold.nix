{ lib, config, ... }:
# Holds this host's services down at boot, for a restore onto an empty host: the Phase B
# cutover, or a disaster recovery (docs/backups.md). It replaces masking units at the
# GRUB prompt, which needs a console in time to catch the boot.
#
# Without it, a fresh host starts every stack against empty data directories:
# - Traefik requests certificates for every hostname at once (Let's Encrypt's weekly
#   limits turn a second failed attempt into days without TLS);
# - apps initialise empty instances that a later restore half-replaces (Nextcloud's
#   installer, Sharkey under its permanent name, the *arr apps reading an empty library
#   as "everything was deleted");
# - Backrest's schedules back the *empty* state up over the good snapshots, after which
#   retention starts forgetting the originals.
#
# What a hold does is only to leave units out of the boot targets. They all still exist:
# `systemctl start compose-databases` works for `postgres-restore`, and the restore tools
# leave stopped units stopped. Releasing a hold is a commit, `nh os boot`, and a reboot,
# so everything then starts in dependency order (`nh os switch` would not start units
# that only gained a `wantedBy`).
let
  cfg = config.restoreHold;
  none = lib.mkForce [ ];
in
{
  options.restoreHold = {
    stacks = lib.mkEnableOption ''
      holding every compose stack, and the timers that act on their data, out of the boot
      targets
    '';
    backups = lib.mkEnableOption ''
      holding Backrest out of the boot targets, so no backup runs until the restored
      state has been verified
    '';
  };

  config = {
    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.stacks (
        lib.mapAttrs' (
          name: _: lib.nameValuePair "compose-${name}" { wantedBy = none; }
        ) config.compose-stacks.stacks
      ))
      # Units that `requires` a stack and are wanted by multi-user.target pull it up
      # with them, hold or not. (Units wanted by their own stack, like garage-website,
      # need nothing here.)
      (lib.mkIf cfg.stacks {
        auth-lldap-bootstrap.wantedBy = none;
        crowdsec-machine-bootstrap.wantedBy = none;
      })
      (lib.mkIf cfg.backups { backrest.wantedBy = none; })
    ];

    # The timers that would act on a stack's data while it is being restored:
    # paperless-export runs `document_exporter --delete`, which against a database not
    # yet restored clears the export directory; nextcloud-cron would run background jobs
    # against a half-restored instance as soon as anyone starts it by hand.
    systemd.timers = lib.mkIf cfg.stacks {
      paperless-export.wantedBy = none;
      nextcloud-cron.wantedBy = none;
    };
  };
}
