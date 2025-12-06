{ inputs, pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
    mutableExtensionsDir = false;
    profiles =
      let
        defaultExtensions = with pkgs.vscode-marketplace; [
          mkhl.direnv
          jnoortheen.nix-ide
          aaron-bond.better-comments
          streetsidesoftware.code-spell-checker
          mk12.better-git-line-blame
          mhutchie.git-graph
          oderwat.indent-rainbow
          yzhang.markdown-all-in-one
          davidanson.vscode-markdownlint
          yutengjing.open-in-external-app
          johnpapa.vscode-peacock
          gruntfuggly.todo-tree
          vscode-icons-team.vscode-icons
          skellock.just
        ];
        defaultUserSettings = {
          "git.autofetch" = "all";
          "git.enableSmartCommit" = true;
          "git.confirmSync" = false;
          "editor.multiCursorModifier" = "ctrlCmd";
          "editor.formatOnSave" = true;
          "workbench.iconTheme" = "vscode-icons";
        };
        defaultKeybindings = [
          # Browser-like tab navigation, smth that should be the default let's be honest...
          {
            "key" = "ctrl+tab";
            "command" = "workbench.action.nextEditor";
          }
          {
            "key" = "ctrl+shift+tab";
            "command" = "workbench.action.previousEditor";
          }
          # Save all files
          {
            "key" = "ctrl+shift+s";
            "command" = "workbench.action.files.saveFiles";
          }
        ];
      in
      {
        default = {
          extensions = defaultExtensions;
          userSettings = defaultUserSettings;
          keybindings = defaultKeybindings;
        };
        ansible = {
          extensions =
            with pkgs.vscode-marketplace;
            [
              ms-python.python
              redhat.vscode-commons
              redhat.ansible
              redhat.vscode-yaml
              ms-azuretools.vscode-containers
              grafana.grafana-alloy
              timonwong.shellcheck
              bmalehorn.shell-syntax
              hashicorp.terraform
            ]
            ++ defaultExtensions;
          userSettings = defaultUserSettings;
          keybindings = defaultKeybindings;
        };
        astro = {
          extensions =
            with pkgs.vscode-marketplace;
            [
              astro-build.astro-vscode
              dbaeumer.vscode-eslint
              whtouche.vscode-js-console-utils
              unifiedjs.vscode-mdx
              bradlc.vscode-tailwindcss
            ]
            ++ defaultExtensions;
          userSettings = defaultUserSettings;
          keybindings = defaultKeybindings;
        };
      };
  };

  stylix.targets.vscode.profileNames = [
    "default"
    "ansible"
    "astro"
  ];
}
