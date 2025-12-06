{ lib, config, ... }:
let
  cfg = config.locale;
in
{
  options.locale = {
    timezone = lib.mkOption {
      default = "Europe/Brussels";
    };
    defaultLocale = lib.mkOption {
      default = "en_US.UTF-8";
    };
    extraLocale = lib.mkOption {
      default = "fr_BE.UTF-8";
    };
  };

  config = {
    time.timeZone = cfg.timezone;

    i18n.defaultLocale = cfg.defaultLocale;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = cfg.extraLocale;
      LC_IDENTIFICATION = cfg.extraLocale;
      LC_MEASUREMENT = cfg.extraLocale;
      LC_MONETARY = cfg.extraLocale;
      LC_NAME = cfg.extraLocale;
      LC_NUMERIC = cfg.extraLocale;
      LC_PAPER = cfg.extraLocale;
      LC_TELEPHONE = cfg.extraLocale;
      LC_TIME = cfg.extraLocale;
    };
  };
}
