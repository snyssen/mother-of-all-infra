variable "public_key" {
  type        = string
  description = "SSH public key (the key itself, not a path) allowed to log in as root when the VM is first created. Ignored afterwards: see the keypair's lifecycle in main.tf."
  # blackfog's key. The live keypair still holds an older key from the initial creation;
  # that difference is ignored.
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68A6FS8yzwzaOUsoKHL9bc+2gB1P5OQriFjEWzG/LH snyssen@blackfog"
}
