{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.comin;
in
{
  imports = [
    inputs.comin.nixosModules.comin
  ];

  options.comin = {
    enable =
      lib.mkEnableOption "comin - GitOps for NixOS Servers and Laptops (https://github.com/nlewo/comin)"
      // {
        default = true;
      };
    desktop.enable = lib.mkEnableOption "comin desktop integration";
  };

  # TODO: use options
  # TODO: services.comin.sshAllowedSignersPath
  config = lib.mkIf cfg.enable {
    services.comin = {
      enable = true;
      remotes = [
        {
          name = "mother-of-all-infra";
          url = "https://github.com/snyssen/mother-of-all-infra";
          poller.period = 300; # I find the default of 60 seconds way too aggressive
        }
      ];
      desktop.enable = cfg.desktop.enable;
    };
  };
}
