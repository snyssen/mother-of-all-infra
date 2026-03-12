# Setup a New Machine: Post-Deployment Checklist

**Duration**: 5–15 minutes (optional; mostly verification and cleanup)

This phase handles tasks that cannot be automated and must happen after `nixos-anywhere` deployment. In most cases with a complete configuration, this phase is minimal or empty.

## Prerequisites

You must have completed [Setup New Machine - Deployment](./Setup%20New%20Machine%20-%20Deployment.md):

✅ `nixos-anywhere` completed successfully
✅ Target system rebooted
✅ System is reachable (via Tailscale or SSH)
✅ Temporary deployment files cleaned up from admin host

## Step 1: Verify Core Functionality

### 1.1 System Identity

Confirm the machine has the correct identity:

```sh
# Log into target
ssh root@${TARGET_HOSTNAME}

# Verify hostname
hostname
# Should print: ${TARGET_HOSTNAME}

# Verify NixOS version
nixos-version
```

### 1.2 Storage and Filesystems

Verify disk layout is correct:

```sh
# Check disks and partitions
lsblk

# Check mount points
mount | grep -E "^/(dev|/)"

# Check available space
df -h
```

### 1.3 Network Connectivity

Verify network is working:

```sh
# Check IP addresses
ip addr show

# Check routing
ip route show

# Test internet connectivity
ping 8.8.8.8  # or any external host
```

### 1.4 Secrets Decryption (if configured)

Verify secrets were decrypted and placed in `/run/secrets/`:

```sh
# List available secrets
ls -la /run/secrets/

# Verify a secret is readable
cat /run/secrets/tailscale/authKey
# Should print the actual secret value, not encrypted text
```

If this fails:
- Check SSH host key exists: `ls -la /etc/ssh/ssh_host_ed25519_key`
- Check age key can be found by sops-nix
- Review systemd logs: `journalctl -u systemd-sops-setup`

### 1.5 Clean Up LUKS Encryption Files (if using disk encryption)

If you used LUKS encryption with a keyfile, clean up the temporary files on the target:

```sh
# Delete the binary keyfile from the target (it's no longer needed after setup)
ssh root@${TARGET_IP} "rm -f /key/${TARGET_HOSTNAME}"

# Verify it's gone
ssh root@${TARGET_IP} "ls -la /key/ 2>/dev/null || echo 'Directory empty or removed'"
```

Also delete the temporary password file from the admin host:

```sh
# On admin host
rm -f /tmp/${TARGET_HOSTNAME}-luks-password.txt
rm -f /tmp/secret.key  # If you used this filename
```

**Why**:
- The binary keyfile on the target is only needed during disk setup. Keeping it in `/key/` is a security risk.
- The password file on the admin host should be deleted to avoid storing credentials.
- The actual LUKS encryption keys remain secure in the encrypted LUKS header; these temporary files are just used for initial setup.

## Step 2: Verify Tailscale (if configured)

If Tailscale is enabled in the NixOS configuration:

```sh
# On target
tailscale status
# Should show: Connected

# On target, check if SSH is enabled
tailscale status | grep ssh
# If "ssh" appears, Tailscale SSH is active

# From admin host, verify reachability
ping <target-tailscale-ip>
# Should respond

# Attempt SSH via Tailscale
ssh root@${TARGET_HOSTNAME}  # May work if DNS is configured
# or
ssh root@<target-tailscale-ip>
```

If Tailscale didn't auto-connect:
- Verify `tailscale/authKey` secret is present (Step 1.4)
- Check Tailscale service logs: `journalctl -u tailscaled`
- Review configuration: `cat /etc/nixos/hosts/${TARGET_HOSTNAME}/configuration.nix | grep -A5 tailscale`

## Step 3: Verify SSH Host Keys

The target's SSH host keys should have been deployed and are now active:

```sh
# From admin host, verify the host key
ssh-keyscan ${TARGET_HOSTNAME} 2>/dev/null | grep -v "^#"

# Check that the key matches what you expect
cat /etc/ssh/ssh_host_ed25519_key.pub  # On target
```

If you regenerated SSH host keys and want the same keys on the next deployment, they're now in place.

## Step 4: Attic Cache Authentication (Optional)

If your NixOS configuration uses binary caching from Attic, the cache client should be pre-configured. However, authentication tokens must be set up.

### 4.1 Generate Attic Token (if cache not done during pre-deployment)

On the **attic server** (if you have one), generate a token for the new machine:

```sh
# On attic server
docker exec attic atticadm make-token \
  -f /attic/attic.toml \
  --sub snyssen \
  --validity 365d \
  --create-cache "snyssen-*" \
  --push "snyssen-*" \
  --pull "snyssen-*" \
  --configure-cache "snyssen-*"
```

This outputs a token like: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

### 4.2 Log Into Attic on Target

On the **target machine**, authenticate with the token:

```sh
# On target
attic login snyssen-infra https://attic.snyssen.be ${ATTIC_TOKEN}
# Replace ${ATTIC_TOKEN} with the token from step 4.1
```

Verify it works:

```sh
# Should succeed
attic cache list
```

### 4.3 Configure as Persistent Secret (Recommended)

For persistent cache authentication across reboots, add the token to the target's secrets:

```sh
# On admin host
just sops-update nix/hosts/${TARGET_HOSTNAME}/data/secrets.yaml
```

Add:

```yaml
attic:
  authToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

Then update the NixOS configuration to load it:

```nix
# nix/hosts/${TARGET_HOSTNAME}/configuration.nix
sops.secrets."attic/authToken" = {
  sopsFile = ./data/secrets.yaml;
  path = "/root/.config/attic/credentials.toml";
};
```

After the next `nixos-rebuild`, attic authentication will be automatic.

## Step 5: Manual Configuration (if needed)

For any configuration that cannot be automated through NixOS (hardware tweaks, BIOS settings, etc.), perform those now. Examples:

- **BIOS settings**: Power management, boot order, virtualization flags
- **Physical hardware**: Verify all drives are recognized, fans working, etc.
- **Network**: Configure static IPs, VPN connections not in Nix
- **Users**: Set passwords for non-root users (if not declarative)

## Step 6: Commit Configuration to Git

Once the machine is stable and verified, commit your new NixOS configuration:

```sh
# On admin host
git add nix/hosts/${TARGET_HOSTNAME}/
git commit -m "Add NixOS configuration for ${TARGET_HOSTNAME}"
git push
```

This ensures your machine's configuration is version-controlled and can be reproduced.

## Step 7: Document (Optional)

If the new machine requires operational documentation, add it to the repository:

```sh
# Add or update documentation
vim docs/machines/${TARGET_HOSTNAME}.md
# Describe purpose, hardware, special config, etc.

git add docs/machines/${TARGET_HOSTNAME}.md
git commit -m "Document ${TARGET_HOSTNAME} machine"
git push
```

## Summary

✅ System identity verified
✅ Storage and networking verified
✅ Secrets decrypted and accessible
✅ Tailscale connected (if configured)
✅ SSH host keys in place
✅ Attic cache authenticated (optional)
✅ Any manual configuration completed
✅ Configuration committed to git

## Troubleshooting

### System won't boot
- Check that hardware configuration was properly generated
- Verify disko config matches actual hardware
- Boot into a live environment and check logs in `/var/log`

### Secrets not decrypting
- Verify age key exists: `ls /etc/ssh/ssh_host_ed25519_key`
- Check age key is readable by sops: `cat /etc/ssh/ssh_host_ed25519_key`
- Review sops-nix activation logs: `journalctl -u sops`

### Can't SSH in
- Verify SSH server is enabled: `systemctl status sshd`
- Check SSH keys are in place (if deploying user keys): `ls ~/.ssh/`
- Verify firewall allows SSH: `nft list ruleset` or `iptables -L`
- Check for IP/network issues: `ip addr` and `ip route`

### Tailscale won't connect
- Verify authKey secret exists: `/run/secrets/tailscale/authKey`
- Check tailscale service: `systemctl status tailscaled`
- Manually start: `tailscale up -auth-key=${AUTHKEY}`
- View logs: `journalctl -u tailscale-autoconnect`

## What's Next?

Your machine is now ready for use. Depending on its purpose:

- **Desktop**: Install additional packages, set up user environments in Home Manager
- **Server**: Configure services (containers, databases, monitoring)
- **Hypervisor**: Set up virtual machines

All further configuration changes should be made through the NixOS configuration files (Nix, Home Manager, Ansible) and deployed with `nixos-rebuild` or `deploy-rs`.
