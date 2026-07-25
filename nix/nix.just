alias nhr := nix-remote-install
alias nbc := nix-build-cache
alias nbcs := nix-build-cache-sign

# Build NixOS configuration and push result to the S3 binary cache
nix-build-cache host=hostname:
  nh os build -H {{host}}
  nix copy --to 's3://cache?endpoint=https://s3.snyssen.be&region=home' ./result

# Build NixOS configuration and push result to the S3 binary cache, signing the build with a private key
nix-build-cache-sign host=hostname keyFile="/run/secrets/nix-caches/cache_snyssen_be/signing_key":
  nh os build -H {{host}}
  nix copy --to 's3://cache?endpoint=https://s3.snyssen.be&region=home' --option secret-key-files "{{keyFile}}" ./result

# Update NixOS configuration on a remote host using nh (requires tailscale for DNS and root SSH access)
nix-remote-install action host ip=host:
  nh os {{action}} -H {{host}} --target-host=root@{{ip}}

# Check that flake builds correctly
nix-check:
  nix flake check
