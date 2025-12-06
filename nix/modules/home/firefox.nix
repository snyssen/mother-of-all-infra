{ lib, config, pkgs, inputs, ... }:
let cfg = config.myHomeManager.firefox;
in {
  options.myHomeManager.firefox = {
    user = lib.mkOption { default = "snyssen"; };
  };

  programs.firefox = {
    enable = true;
    # from: https://github.com/Kreyren/nixos-config/blob/bd4765eb802a0371de7291980ce999ccff59d619/nixos/users/kreyren/home/modules/web-browsers/firefox/firefox.nix#L116-L148
    # For info on possible settings: https://mozilla.github.io/policy-templates/
    policies = {
      AppAutoUpdate = false; # Disable automatic application update
      BackgroundAppUpdate =
        false; # Disable automatic application update in the background, when the application is not running.
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true; # Disable Firefox Sync
      DisableFirefoxScreenshots = true; # No screenshots?
      DisableMasterPasswordCreation =
        true; # To be determined how to handle master password
      DisableProfileImport =
        true; # Purity enforcement: Only allow nix-defined profiles
      DisableProfileRefresh =
        true; # Disable the Refresh Firefox button on about:support and support.mozilla.org
      DisableSetDesktopBackground =
        true; # Remove the “Set As Desktop Background…” menuitem when right clicking on an image, because Nix is the only thing that can manage the backgroud
      DisplayMenuBar = "default-off";
      DisplayBookmarksToolbar = "always";
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFormHistory = true;
      DisablePasswordReveal = true;
      DontCheckDefaultBrowser = true;
      OfferToSaveLogins = false;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        EmailTracking = true;
        # Exceptions = ["https://example.com"]
      };
      EncryptedMediaExtensions = { Enabled = false; };
      ExtensionUpdate = false;
      FirefoxHome = {
        Search = false;
        TopSites = false;
        SponsoredTopSites = false;
        Highlights = false;
        Pocket = false;
        SponsoredPocket = false;
        Snippets = false;
        Locked = true;
      };
      FirefoxSuggest = {
        WebSuggestions = false;
        SponsoredSuggestions = false;
        ImproveSuggest = false;
        Locked = true;
      };
      NoDefaultBookmarks = true;
      PasswordManagerEnabled = false;
    };
    profiles.${cfg.user} = {
      extensions.packages =
        with inputs.firefox-addons.packages."${pkgs.system}"; [
          proton-pass
          ublock-origin
          floccus
          new-tab-override
        ];
      settings = {
        "browser.startup.homepage" = "https://dash.snyssen.be";
        "widget.disable-swipe-tracker" =
          "true"; # Disable annoying swipe gesture to back and forward in history
      };
      search.engines = {
        "Kagi" = {
          urls = [{ template = "https://kagi.com/search?q={searchTerms}"; }];
          icon = "https://kagi.com/asset/de5eec9/favicon-16x16.png";
        };
      };
      search.default = "Kagi";
      search.force =
        true; # https://github.com/nix-community/home-manager/issues/3698
    };
  };
  stylix.targets.firefox.profileNames = [ "${cfg.user}" ];
}
