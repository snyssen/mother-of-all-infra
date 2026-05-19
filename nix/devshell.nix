{ pkgs }:
pkgs.mkShell {
  # Add build dependencies
  packages = with pkgs; [
    nixfmt
    nixd
    just
    pre-commit
    # TODO: Add project specific dependencies
    ansible
    ansible-lint
    glibcLocales # otherwise ansible cannot run
    grafana-alloy
    terraform
    age
    ssh-to-age
    sops
    openstackclient
  ];

  # Add environment variables
  env = { };

  # Load custom bash code
  shellHook = ''
    bash scripts/git-main-safety-check.sh warn
    echo ""
    echo -e "This devshell uses '\e[32;1mjust\e[0m' as a task runner."
    just --list
    echo -e "\e[0;95mNOTE:\e[0m If this is your first time on this repo, running '\e[32;1mjust setup\e[0m' is recommended in order to initialize the development environment."
    echo ""
  '';
}
