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
  ];

  # Add environment variables
  env = { };

  # Load custom bash code
  shellHook = ''
    just setup
    echo -e "\e[32;1mReady! \e[0m"
  '';
}
