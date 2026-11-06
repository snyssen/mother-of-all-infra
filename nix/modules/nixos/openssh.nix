# Key-only SSH, shared by every host that runs sshd. Tailscale SSH is the usual way
# in; this stays as the fallback for when Tailscale itself is broken.
{ lib, ... }:
{
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      # Not implied by the above: with PAM (the NixOS default), keyboard-interactive
      # still prompts for the account's password.
      KbdInteractiveAuthentication = false;
      # mkDefault so it yields to openstack-config.nix on ingress, which sets
      # "prohibit-password" so root can log in with the Gandi keypair it fetches from
      # instance metadata at boot.
      PermitRootLogin = lib.mkDefault "no";
    };
  };
}
