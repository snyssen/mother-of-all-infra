# Setup a New Machine: Deployment Walkthrough

**Duration**: 30–90 minutes (target machine interaction + remote deployment)

This phase boots the target machine to a live environment and runs `nixos-anywhere` to deploy the NixOS system. Steps alternate between the **target host** (in live environment) and **admin host** (your development machine).

## Prerequisites

You must have completed [Setup New Machine - Pre-Deployment](./Setup%20New%20Machine%20-%20Pre-Deployment.md):

✅ NixOS configuration created
✅ SSH keypairs generated and staged
✅ Age keys authorized in `.sops.yaml`
✅ Secrets encrypted
✅ Flake builds successfully
✅ Deployment credentials prepared

## Overview

1. **Part A**: Boot target to live environment, perform minimal setup (~5–10 minutes)
2. **Part B**: Run `nixos-anywhere` from admin host (~20–60 minutes)
3. **Part C**: Verify system booted successfully
4. **Part D**: Clean up temporary files from admin host

## Part A: Prepare Target Machine (Live Environment)

### A.1 Boot NixOS Minimal Image

Prepare a bootable USB stick with the [NixOS minimal image](https://nixos.org/download/):

- Download from https://nixos.org/download/
- Write to USB using Etcher, dd, or Ventoy
- Boot the target machine from the USB stick

Wait for the minimal ISO to fully boot (you'll see a login prompt or shell).

### A.2 (Optional) Set Keyboard Layout

If your keyboard is not QWERTY, change the layout. For example, Belgian AZERTY:

```sh
sudo loadkeys /etc/kbd/keymaps/i386/azerty/be-latin1.map.gz
```

Adjust the path based on your keyboard layout. Common layouts:
- Belgian: `i386/azerty/be-latin1.map.gz`
- French: `i386/azerty/fr-latin1.map.gz`
- German: `i386/qwertz/de.map.gz`

### A.3 (Optional) Connect to WiFi

If you need WiFi (not needed if connected via Ethernet):

```sh
nmtui
```

Follow the on-screen menu to scan and connect to your network.

### A.4 Set Temporary Root Password

Used only by `nixos-anywhere` to log in. Retrieve the password you generated during pre-deployment:

```sh
sudo passwd
# Enter the password from /tmp/${HOSTNAME}-root-password.txt on admin host
# Confirm it
```

**Important**: This password only exists during the live environment and is discarded after reboot.

### A.5 Get Target IP Address

Determine the target's IP address so the admin host can connect via SSH:

**For Ethernet (DHCP)**:
```sh
ip addr show
# Look for inet address on eth0 or ens* interface, e.g., 192.168.1.50
```

**For VPS/Cloud targets**: Use the IP provided by your cloud provider instead.

**For local networks if DHCP fails**: Configure a static IP:
```sh
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
```

Note the IP address (e.g., `192.168.1.50`); you'll need it for the next part.

### A.6 Verify Disk Layout

Ensure the disks available match your disko configuration:

```sh
lsblk
```

Example output:
```
NAME                 MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda                    8:0    0  500G  0 disk
sdb                    8:16   0    2T  0 disk
nvme0n1              259:0    0  1.8T  0 disk
```

**Important**: Verify that:
- The correct disk(s) are present (will be formatted and all data erased)
- The number and size of disks match your disko config
- You're formatting the right disks (double-check if you have multiple targets around)

If the layout doesn't match your configuration, **stop here** and adjust your disko config on the admin host before continuing.

### A.7 Ready for Deployment

You now have:
- ✅ Live environment running
- ✅ Root password set
- ✅ IP address known
- ✅ Disks verified

All remaining steps happen on the **admin host**. You can now leave the target machine idle; it will reboot automatically during deployment.

---

## Part B: Run nixos-anywhere (From Admin Host)

### B.1 Verify Admin Host Prerequisites

On your admin host, ensure:

```sh
# You're in the devshell
nix flake --version  # Should succeed
age --version        # Should be available
ssh -V               # Should be available

# Verify your staging directory exists
ls -la /tmp/${HOSTNAME}-deploy/
# Should show ssh keys and other staged files
```

### B.2 Construct the nixos-anywhere Command

Build the command step-by-step. Start with the base:

```sh
TARGET_IP="192.168.1.50"  # Replace with target's actual IP
TARGET_HOSTNAME="hypervisor"  # Replace with your hostname
FLAKE_PATH="."  # Or /path/to/repo if not in working directory
EXTRA_FILES="/tmp/${TARGET_HOSTNAME}-deploy"
```

Then the full command:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake "${FLAKE_PATH}#${TARGET_HOSTNAME}" \
  --target-host "root@${TARGET_IP}" \
  --generate-hardware-config nixos-generate-config \
    "nix/hosts/${TARGET_HOSTNAME}/hardware-configuration.nix" \
  --extra-files "${EXTRA_FILES}"
```

#### For LUKS Disk Encryption (Dual-Unlock)

If using LUKS with both keyfile and password:

```sh
  --disk-encryption-keys \
    "/tmp/secret.key" "/tmp/${TARGET_HOSTNAME}-luks-password.txt"
```

This passes the backup password to disko. The binary keyfile is already included via `--extra-files`, which copies `/tmp/${TARGET_HOSTNAME}-deploy/key/${TARGET_HOSTNAME}` → `/key/${TARGET_HOSTNAME}` on the target.

**Disko will then**:
1. Try mounting the USB key and unlocking with the binary keyfile (primary)
2. Fall back to the password if USB isn't found (secondary)

#### File Ownership (if needed)

If your SSH keypair file permissions need adjustment after copying:

```sh
--chown /etc/ssh/ssh_host_ed25519_key 0:0 \
--chown /etc/ssh/ssh_host_ed25519_key.pub 0:0
```

Or for desktop user keys:

```sh
--chown /home/snyssen/.ssh/id_ed25519 1000:1000 \
--chown /home/snyssen/.ssh/id_ed25519.pub 1000:1000
```

(Replace `1000:1000` with the actual `uid:gid` of the snyssen user.)

### B.4 Run nixos-anywhere

Execute the full command. For example, with LUKS and SSH keys:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#${TARGET_HOSTNAME} \
  --target-host root@${TARGET_IP} \
  --generate-hardware-config nixos-generate-config \
    nix/hosts/${TARGET_HOSTNAME}/hardware-configuration.nix \
  --extra-files /tmp/${TARGET_HOSTNAME}-deploy \
  --disk-encryption-keys \
    "/tmp/secret.key" "/tmp/${TARGET_HOSTNAME}-luks-password.txt" \
  --chown /etc/ssh/ssh_host_ed25519_key 0:0 \
  --chown /etc/ssh/ssh_host_ed25519_key.pub 0:0
```

Or without LUKS:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#${TARGET_HOSTNAME} \
  --target-host root@${TARGET_IP} \
  --generate-hardware-config nixos-generate-config \
    nix/hosts/${TARGET_HOSTNAME}/hardware-configuration.nix \
  --extra-files /tmp/${TARGET_HOSTNAME}-deploy \
  --chown /etc/ssh/ssh_host_ed25519_key 0:0 \
  --chown /etc/ssh/ssh_host_ed25519_key.pub 0:0
```

**What happens next:**

1. `nixos-anywhere` prompts for SSH password (enter the temporary password from A.4)
2. Kexec image boots on target (you'll see progress messages)
3. Disko partitions and formats disks (watch for warnings about data loss)
4. If using LUKS: Disko sets up dual unlock (keyfile + password)
5. Nix closure builds and copies to target
6. NixOS configuration activates
7. Target automatically reboots

**Expected time**: 20–60 minutes depending on network speed and disk performance

### B.5 Monitor the Process

You'll see messages like:

```
activating the configuration...
setting up /etc/...
creating symlinks...
...
running activation script
...
Installation finished. No error reported.
```

When you see "Installation finished", the deployment succeeded. The target will reboot automatically.

### B.6 Troubleshooting Common Errors

**Error: "Password authentication failed"**
- Verify root password was set correctly (A.4)
- Verify target's live environment is still running
- Try connecting manually: `ssh root@${TARGET_IP}`

**Error: "Disks not found" or "cannot find partition"**
- Stop the command (`Ctrl+C`)
- Go back to target machine (A.6) and verify disk layout with `lsblk`
- Update disko config if needed
- Try again

**Error: "Permission denied" or "timeout"**
- Verify network connectivity: ping target from admin host
- Verify target's IP address is correct

**Kexec fails silently or hangs**
- May indicate insufficient RAM in target (need ≥1.5GB)
- Try rerunning; sometimes network delays cause timeouts

---

## Part C: Verify Successful Deployment

### C.1 Wait for Target to Reboot

After "Installation finished", the target will:
1. Unmount filesystems
2. Reboot automatically (may take 1–5 minutes)

Do not interrupt the power; let it complete.

### C.2 Verify System is Reachable

Once the target finishes rebooting, it should be reachable. If Tailscale is configured, add it to Tailscale and verify:

```sh
# On admin host, if target is on Tailscale
tailscale list | grep ${TARGET_HOSTNAME}
# Should show the target in the list

# Try to ping via Tailscale IP
ping <target-tailscale-ip>
```

Or via regular SSH (if configured):

```sh
ssh root@${TARGET_IP}
# or
ssh snyssen@${TARGET_HOSTNAME}  # if user is configured
```

### C.3 Verify Secrets Decrypted

If secrets are configured, verify they were decrypted during boot:

```sh
ssh root@${TARGET_IP} "cat /run/secrets/tailscale/authKey"
# Should print the actual auth key (not encrypted)
```

If this fails with "No such file", the secret wasn't properly decrypted. Check:
- Is the age key in the correct location? (`/etc/ssh/ssh_host_ed25519_key`)
- Is the secret file re-encrypted with the target's age key?
- Are there errors in the NixOS configuration?

### C.4 Optional: Login and Quick Checks

Once logged in:

```sh
# Verify hostname
hostname  # Should show your target hostname

# Check disk layout
lsblk  # Should show formatted partitions

# Check LUKS (if encrypted)
dmsetup status  # Should show luks partition is open

# Verify Tailscale (if configured)
tailscale status  # Should show connected to tailnet
```

---

## Part D: Clean Up Admin Host

### D.1 Delete Temporary Deployment Files

```sh
rm -rf /tmp/${HOSTNAME}-deploy/
rm -f /tmp/${HOSTNAME}-root-password.txt
rm -f /tmp/${HOSTNAME}-luks-password.txt
```

### D.2 Update SSH known_hosts

If this is a new machine, `known_hosts` may have a stale entry. Remove it:

```sh
ssh-keygen -R ${TARGET_IP}
# or for hostname
ssh-keygen -R ${TARGET_HOSTNAME}
```

This allows SSH to accept the new host key without warnings.

## Summary

✅ Target machine deployed with NixOS
✅ SSH keypairs and secrets in place
✅ System booted successfully
✅ Temporary deployment files cleaned up

**Next step**: Proceed to [Setup New Machine - Post-Deployment](./Setup%20New%20Machine%20-%20Post-Deployment.md)
