{ pkgs, ... }:
{
  config = {
    services.jellyfin = {
      enable = true; # Will be available on http://localhost:8096/
      openFirewall = false; # This is for local use
      user = "snyssen";
    };

    systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD"; # or i965 for older GPUs
    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "iHD";
    };

    hardware.graphics = {
      enable = true;

      extraPackages = with pkgs; [
        intel-ocl # Generic OpenCL support

        # For Broadwell and newer (ca. 2014+), use with LIBVA_DRIVER_NAME=iHD:
        intel-media-driver

        # For 13th gen and newer:
        intel-compute-runtime

        # For 11th gen and newer:
        vpl-gpu-rt
      ];
    };
  };
}
