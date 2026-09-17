{ lib, ... }:
{
  options.domains = {
    main = lib.mkOption {
      type = lib.types.str;
      description = ''
        Primary public domain this host's services are reachable under. Referenced by
        stacks instead of hardcoding a literal domain, so the whole host can be pointed
        at a different domain in one place (e.g. to run a second host in parallel under
        its own domain during a migration).
      '';
    };

    team = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Secondary/team public domain, if this host serves one.";
    };
  };
}
