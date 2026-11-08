# The hypervisor recipes act on hypervisor-01 unless told otherwise. During the Phase B
# cutover the test hypervisor (`hypervisor`) still exists, so:
# - inspection recipes take the host as an optional *last* argument
#   (`just hypervisor-vm-list hypervisor`);
# - the two playbook recipes, which change things, take it as a required *first*
#   argument, so they never act on a hypervisor by default
#   (`just hypervisor-provision-vms hypervisor-01`).
hypervisor_host := "hypervisor-01"

# SSH into a hypervisor
hypervisor-ssh host=hypervisor_host:
  ssh {{host}}

# List all defined VMs on a hypervisor (running and stopped)
hypervisor-vm-list host=hypervisor_host:
  ssh {{host}} virsh list --all

# Start a VM
hypervisor-vm-start vm host=hypervisor_host:
  ssh {{host}} virsh start {{vm}}

# Gracefully shut down a VM
hypervisor-vm-stop vm host=hypervisor_host:
  ssh {{host}} virsh shutdown {{vm}}

# Reboot a VM
hypervisor-vm-reboot vm host=hypervisor_host:
  ssh {{host}} virsh reboot {{vm}}

# Force-off a VM (hard power cut — use only if graceful shutdown fails)
hypervisor-vm-destroy vm host=hypervisor_host:
  ssh {{host}} virsh destroy {{vm}}

# Open an interactive serial console to a VM (press Ctrl-] to exit)
hypervisor-vm-console vm host=hypervisor_host:
  ssh -t {{host}} virsh console {{vm}}

# Show detailed info about a VM
hypervisor-vm-info vm host=hypervisor_host:
  ssh {{host}} virsh dominfo {{vm}}

# Trigger a btrfs scrub on a pool (pool: vmstore or bulk); waits for completion
hypervisor-btrfs-scrub pool host=hypervisor_host:
  ssh root@{{host}} btrfs scrub start -B /mnt/{{pool}}

# Show the status of the last btrfs scrub for a pool
hypervisor-btrfs-scrub-status pool host=hypervisor_host:
  ssh root@{{host}} btrfs scrub status /mnt/{{pool}}

# Show btrfs filesystem usage for a pool
hypervisor-btrfs-usage pool host=hypervisor_host:
  ssh root@{{host}} btrfs filesystem usage /mnt/{{pool}}

# Show per-device I/O error counters for a pool
hypervisor-btrfs-stats pool host=hypervisor_host:
  ssh root@{{host}} btrfs device stats /mnt/{{pool}}

# Show btrfs device listing and filesystem info for a pool
hypervisor-btrfs-devices pool host=hypervisor_host:
  ssh root@{{host}} btrfs filesystem show /mnt/{{pool}}

# Build a hypervisor's selected NixOS VM disk images locally and copy them to it
[working-directory: 'ansible']
hypervisor-build-vm-images host *flags:
  ansible-playbook playbooks/libvirt-image-build.ansible.yml -i hosts/prod.yml -e libvirt_hypervisor={{host}} {{flags}}

# Provision a hypervisor's VMs (add -e libvirt_vms_only=<vm>[,<vm>...] for some only)
[working-directory: 'ansible']
hypervisor-provision-vms host *flags:
  ansible-playbook playbooks/libvirt-provision.ansible.yml -i hosts/prod.yml -e libvirt_hypervisor={{host}} {{flags}}
