{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ai;
in
{
  options.ai = {
    ollama = {
      enable = lib.mkEnableOption "Ollama service";
      models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of Ollama models to preload, see https://ollama.com/library";
      };
    };
    open-webui = {
      enable = lib.mkEnableOption "Open WebUI service";
      port = lib.mkOption {
        type = lib.types.int;
        default = 8888;
        description = "Port for Open WebUI service";
      };
    };
    opencode = {
      enable = lib.mkEnableOption "OpenCode service";
      desktop.enable = lib.mkEnableOption "OpenCode desktop application";
    };
  };

  config = {
    services.ollama = {
      enable = cfg.ollama.enable;
      loadModels = cfg.ollama.models;
    };
    services.open-webui = {
      enable = cfg."open-webui".enable;
      port = cfg."open-webui".port;
    };
    environment.systemPackages =
      [ ]
      ++ lib.optional (cfg.opencode.enable) pkgs.opencode
      ++ lib.optional (cfg.opencode.desktop.enable) pkgs.opencode-desktop;
  };
}
