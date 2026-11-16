alias nhr := nix-remote-install
alias nhra := nix-remote-install-all
alias nb := nix-build
alias nbc := nix-build-cache
alias nbcs := nix-build-cache-sign

# Build NixOS configuration
nix-build host=hostname:
  nh os build -H {{host}}

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

# Run nix-remote-install on every NixOS host but this one (use `nh os switch` here), skipping any given as extra args or unreachable over SSH
nix-remote-install-all action *exclude:
  #!/usr/bin/env bash
  set -uo pipefail
  skip=" {{hostname}} {{exclude}} "
  # Hypervisors last, so their VMs are already done if switching one disturbs them.
  hosts=$(nix eval --raw .#nixosConfigurations --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)' | awk '/^hypervisor/ { last = last $0 "\n"; next } { print } END { printf "%s", last }')
  ok=() failed=() unreachable=()
  for host in $hosts; do
    [[ "$skip" == *" $host "* ]] && continue
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$host" true 2>/dev/null; then
      echo ">>> $host: unreachable over SSH, skipping"
      unreachable+=("$host")
      continue
    fi
    echo ">>> $host: nh os {{action}}"
    if {{just_executable()}} nix-remote-install {{action}} "$host"; then
      ok+=("$host")
    else
      failed+=("$host")
    fi
  done
  echo
  echo "ok:          ${ok[*]:-none}"
  echo "failed:      ${failed[*]:-none}"
  echo "unreachable: ${unreachable[*]:-none}"
  [[ ${#failed[@]} -eq 0 ]]

# Check that flake builds correctly
nix-check:
  nix flake check
