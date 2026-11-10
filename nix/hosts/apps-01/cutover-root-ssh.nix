# Transitional: root over plain SSH, key-only, for the Phase B cutover.
#
# Tailscale SSH (the usual way in) re-authenticates through Authelia, which runs on this
# host and is down until its stacks are released (D8 of
# docs/hypervisor/apps-migration-phase-b.md). Until then, deploys need root over sshd.
# Tailscale SSH takes port 22 on the tailnet address, so this only answers on the LAN
# one: `just nix-remote-install switch apps-01 192.168.1.10`.
#
# Delete this file and its import once Tailscale SSH works again (D8).
{ ... }:
{
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68A6FS8yzwzaOUsoKHL9bc+2gB1P5OQriFjEWzG/LH snyssen@blackfog"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIERQS+yhsr8HU1xoTnIOlJLWD9sJnKbiNQglBH/xaGM7 snyssen@purplehaze"
  ];
}
