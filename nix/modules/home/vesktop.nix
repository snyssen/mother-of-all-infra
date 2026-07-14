{
  flake,
  ...
}:
{

  imports = [ flake.inputs.nixcord.homeModules.nixcord ];

  config = {
    programs.nixcord = {
      enable = true;
      discord.equicord.enable = true;
      vesktop.enable = true;
      config = {
        plugins = {
          crashHandler.enable = true;
          webScreenShareFixes.enable = true;
        };
      };
    };
  };
}
