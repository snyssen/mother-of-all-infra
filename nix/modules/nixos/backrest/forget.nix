{
  lib,
  config,
  pkgs,
  ...
}:
# Bulk "forget everything before <date>" commands, one per side: the repos the primary
# plans write to, and the repos their mirrors write to. Backrest's UI forgets one
# snapshot at a time, and plan retention never touches snapshots another tool made
# (autorestic's), so without this they stay forever or go by hand.
#
# Generated the same way as the restore commands (see restore.nix): a plain script in
# scripts/forget.sh, handed what Nix knows as a JSON manifest. Repos rather than plans,
# because the point is to reach snapshots no plan owns.
let
  cfg = config.backrest;
  inherit (import ./paths.nix) dataDir;

  repoManifest =
    name:
    let
      repo = cfg.repos.${name};
    in
    {
      inherit (repo) uri;
      passwordFile = config.sops.secrets.${repo.passwordSecret}.path;
      env = lib.mapAttrs (_: secretPath: config.sops.secrets.${secretPath}.path) repo.env;
    };

  mkForgetCommand =
    commandName: repoNames:
    pkgs.writeShellApplication {
      name = commandName;
      runtimeInputs = with pkgs; [
        restic
        jq
        coreutils
        gnugrep
        gawk
        findutils
      ];
      text = ''
        MANIFEST=${
          pkgs.writeText "${commandName}-manifest.json" (
            builtins.toJSON {
              command = commandName;
              repos = lib.genAttrs repoNames repoManifest;
            }
          )
        }
        export MANIFEST
        export HOME=${lib.escapeShellArg dataDir}

      ''
      + builtins.readFile ./scripts/forget.sh;
    };

  reposOf = plans: lib.unique (lib.mapAttrsToList (_: plan: plan.repo) plans);
  primaryRepos = reposOf (lib.filterAttrs (_: plan: plan.mirrorOf == null) cfg.plans);
  mirrorRepos = reposOf (lib.filterAttrs (_: plan: plan.mirrorOf != null) cfg.plans);
in
{
  options.backrest.forget = {
    commandName = lib.mkOption {
      type = lib.types.str;
      default = "backrest-forget";
      description = ''
        Name of the command forgetting snapshots older than a cutoff in the repos the
        primary plans write to. Not generated when no plans are declared.
      '';
    };

    offsiteCommandName = lib.mkOption {
      type = lib.types.str;
      default = "backrest-forget-offsite";
      description = ''
        The same, for the repos the mirror plans (`mirrorOf`) write to. Not generated
        when no plan is a mirror.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mapAttrsToList mkForgetCommand (
      lib.optionalAttrs (primaryRepos != [ ]) { ${cfg.forget.commandName} = primaryRepos; }
      // lib.optionalAttrs (mirrorRepos != [ ]) { ${cfg.forget.offsiteCommandName} = mirrorRepos; }
    );
  };
}
