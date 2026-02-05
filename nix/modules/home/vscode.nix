{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.vscode;
in
{
  options.vscode = {
    useUnstable = pkgs.lib.mkEnableOption "Use vscode from nixpkgs-unstable";
  };

  config = {
    programs.vscode = {
      enable = true;
      package = if cfg.useUnstable then pkgs.unstable.vscode.fhs else pkgs.vscode.fhs;
      mutableExtensionsDir = false;
      profiles =
        let
          # Take from same nixpkgs as vscode itself as versions need to be aligned
          versionAlignedExtensions =
            if cfg.useUnstable then
              [
                pkgs.unstable.vscode-extensions.github.copilot
                pkgs.unstable.vscode-extensions.github.copilot-chat
              ]
            else
              [
                pkgs.vscode-extensions.github.copilot
                pkgs.vscode-extensions.github.copilot-chat
              ];
          defaultExtensions =
            with pkgs.vscode-marketplace;
            [
              mkhl.direnv
              jnoortheen.nix-ide
              aaron-bond.better-comments
              streetsidesoftware.code-spell-checker
              mk12.better-git-line-blame
              mhutchie.git-graph
              oderwat.indent-rainbow
              pomdtr.excalidraw-editor
              yzhang.markdown-all-in-one
              davidanson.vscode-markdownlint
              yutengjing.open-in-external-app
              johnpapa.vscode-peacock
              gruntfuggly.todo-tree
              vscode-icons-team.vscode-icons
              skellock.just
              signageos.signageos-vscode-sops
              github.vscode-github-actions
              github.vscode-pull-request-github
            ]
            ++ versionAlignedExtensions;
          defaultUserSettings = {
            "git.autofetch" = "all";
            "git.enableSmartCommit" = true;
            "git.confirmSync" = false;
            "editor.multiCursorModifier" = "ctrlCmd";
            "editor.formatOnSave" = true;
            "workbench.iconTheme" = "vscode-icons";
            "vsicons.dontShowNewVersionMessage" = true;
            "diffEditor.ignoreTrimWhitespace" = false;
            "workbench.editorAssociations" = {
              "*.md" = "vscode.markdown.preview.editor";
            };
            "chat.viewSessions.orientation" = "stacked";
            "chat.tools.urls.autoApprove" = {
              "https://search.nixos.org" = {
                "approveRequest" = true;
                "approveResponse" = false;
              };
              "https://nixos.org" = {
                "approveRequest" = true;
                "approveResponse" = true;
              };
            };
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
            # Copy lines up or down
            {
              "key" = "shift+alt+down";
              "command" = "editor.action.copyLinesDownAction";
              "when" = "editorTextFocus && !editorReadonly";
            }
            {
              "key" = "shift+alt+up";
              "command" = "editor.action.copyLinesUpAction";
              "when" = "editorTextFocus && !editorReadonly";
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
            userSettings = lib.mkMerge [
              {
                "redhat.telemetry.enabled" = false;
              }
              defaultUserSettings
            ];
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
          dotnet = {
            extensions =
              with pkgs.vscode-marketplace;
              [
                ms-dotnettools.vscode-dotnet-runtime
                ms-dotnettools.csharp
                ms-dotnettools.csdevkit
                editorconfig.editorconfig
              ]
              ++ defaultExtensions;
            userSettings = lib.mkMerge [
              defaultUserSettings
            ];
            keybindings = defaultKeybindings;
          };
        };

    };
    stylix.targets.vscode.profileNames = [
      "default"
      "ansible"
      "astro"
      "dotnet"
    ];
  };
}
