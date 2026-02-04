{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rclone;
in
{
  options.rclone = { };

  config = {
    programs.rclone = {
      enable = true;
      package = pkgs.rclone;
      # Example of remote config:
      # remotes = {
      #   b2 = {
      #     config = {
      #       type = "b2";
      #       hard_delete = true;
      #     };
      #     secrets = {
      #       # using sops
      #       account = config.sops.secrets.b2-acc-id.path;
      #       # using agenix
      #       key = config.age.secrets.b2-key.path;
      #     };
      #   };

      #   server.config = {
      #     type = "sftp";
      #     host = "server";
      #     user = "backup";
      #     key_file = "${home.homeDirectory}/.ssh/id_ed25519";
      #   };
      # };
    };
  };
}
