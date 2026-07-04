# This module provides some disaster recovery tools to access raw restic backups
{ pkgs, ... }: {
  home.packages = with pkgs; [
    restic
    restic-browser
  ];
}
