hypervisor_host := "hypervisor"

# SSH into the hypervisor
hypervisor-ssh:
  ssh {{hypervisor_host}}

# List all defined VMs on the hypervisor (running and stopped)
hypervisor-vm-list:
  ssh {{hypervisor_host}} virsh list --all

# Start a VM
hypervisor-vm-start vm:
  ssh {{hypervisor_host}} virsh start {{vm}}

# Gracefully shut down a VM
hypervisor-vm-stop vm:
  ssh {{hypervisor_host}} virsh shutdown {{vm}}

# Reboot a VM
hypervisor-vm-reboot vm:
  ssh {{hypervisor_host}} virsh reboot {{vm}}

# Force-off a VM (hard power cut — use only if graceful shutdown fails)
hypervisor-vm-destroy vm:
  ssh {{hypervisor_host}} virsh destroy {{vm}}

# Open an interactive serial console to a VM (press Ctrl-] to exit)
hypervisor-vm-console vm:
  ssh -t {{hypervisor_host}} virsh console {{vm}}

# Show detailed info about a VM
hypervisor-vm-info vm:
  ssh {{hypervisor_host}} virsh dominfo {{vm}}

# Trigger a btrfs scrub on a pool (pool: vmstore or bulk); waits for completion
hypervisor-btrfs-scrub pool:
  ssh root@{{hypervisor_host}} btrfs scrub start -B /mnt/{{pool}}

# Show the status of the last btrfs scrub for a pool
hypervisor-btrfs-scrub-status pool:
  ssh root@{{hypervisor_host}} btrfs scrub status /mnt/{{pool}}

# Show btrfs filesystem usage for a pool
hypervisor-btrfs-usage pool:
  ssh root@{{hypervisor_host}} btrfs filesystem usage /mnt/{{pool}}

# Show per-device I/O error counters for a pool
hypervisor-btrfs-stats pool:
  ssh root@{{hypervisor_host}} btrfs device stats /mnt/{{pool}}

# Show btrfs device listing and filesystem info for a pool
hypervisor-btrfs-devices pool:
  ssh root@{{hypervisor_host}} btrfs filesystem show /mnt/{{pool}}

# Run the libvirt VM provisioning playbook against the hypervisor (production)
[working-directory: 'ansible']
hypervisor-provision-vms *flags:
  ansible-playbook playbooks/libvirt-provision.ansible.yml -i hosts/prod.yml {{flags}}
