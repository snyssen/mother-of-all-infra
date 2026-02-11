{
  flake,
  ...
}:
{

  imports = [ flake.inputs.nixcord.homeModules.nixcord ];

  config = {
    programs.nixcord = {
      enable = true;
      vesktop.enable = true;
    };
  };
}
