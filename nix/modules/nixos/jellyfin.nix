{ ... }:
{
  config = {
    services.jellyfin = {
      enable = true; # Will be available on http://localhost:8096/
      openFirewall = false; # This is for local use
      user = "snyssen";
    };
  };
}
