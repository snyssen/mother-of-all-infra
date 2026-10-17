# Plain attrset, not a NixOS module — imported directly by service.nix and restore.nix
# so the two agree on these paths without either having to reach into the other.
#
# dataDir doubles as $HOME for everything that shells out to restic: systemd services
# get no $HOME, and without one restic cannot place its metadata cache. That is not
# just a slowdown — restic prints the "unable to open cache" warning as *plain text*
# before its --json output starts, which desyncs any JSON parsing downstream.
{
  dataDir = "/var/lib/backrest/data";
  configPath = "/var/lib/backrest/config/config.json";
}
