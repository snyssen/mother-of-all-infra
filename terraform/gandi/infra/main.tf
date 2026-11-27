# https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_keypair_v2
resource "openstack_compute_keypair_v2" "ingress_keypair" {
  name       = "ingress-keypair"
  public_key = var.public_key

  # The key only matters when the VM is created: from then on NixOS manages SSH access
  # (users.users.*.openssh.authorizedKeys in nix/hosts/ingress). Without this, changing
  # var.public_key would replace the keypair, which replaces the instance (key_pair is
  # create-only). Creation still uses the configured key.
  lifecycle {
    ignore_changes = [public_key]
  }
}

# https://docs.gandi.net/en/cloud/vps/tutorials/terraform_server_creation.html
resource "openstack_compute_instance_v2" "ingress_server" {
  name     = "ingress"
  key_pair = openstack_compute_keypair_v2.ingress_keypair.name
  # V-R2 (1 vCPU, 2 GiB) rather than V-R1 (950 MiB): Traefik's CrowdSec AppSec plugin
  # buffers request bodies, and V-R1's free memory dropped to 131 MiB with no swap.
  # See docs/plans/crowdsec-appsec.md.
  flavor_name     = "V-R2" # See available: `openstack flavor list`, pick "Name".
  security_groups = ["default"]
  power_state     = "active"
  network {
    name = "public"
  }

  block_device {
    uuid                  = "df2d073f-1b79-44c1-a122-dde40d8da17e" # See available: `openstack image list`, pick "ID". Current: "NixOS 24.11 (Vicuna)".
    source_type           = "image"
    volume_size           = 25
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

output "ingress_public_key" {
  value = openstack_compute_keypair_v2.ingress_keypair.public_key
}
output "ingress_ip_v4" {
  value = openstack_compute_instance_v2.ingress_server.access_ip_v4
}
