alias nhr := nix-remote-install
alias nbc := nix-build-cache

# Build NixOS configuration and push result to cache with attic
nix-build-cache host=hostname:
  nh os build -H {{host}}
  attic push snyssen-infra result

# Update NixOS configuration on a remote host using nh (requires tailscale for DNS and root SSH access)
nix-remote-install host ip=host:
  nh os switch -H {{host}} --target-host=root@{{ip}}

# Check that flake builds correctly
nix-check:
  nix flake check
