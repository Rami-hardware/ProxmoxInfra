# Unprivileged LXC container. nesting is what Ubuntu 24.04's systemd needs
# inside an unprivileged container; no Docker runs here (image builds are on
# GitHub-hosted runners), so no keyctl.
resource "proxmox_virtual_environment_container" "ct" {
  node_name     = var.target_node
  vm_id         = var.vmid
  description   = var.description
  unprivileged  = true
  start_on_boot = true
  started       = true

  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = var.name
    ip_config {
      ipv4 {
        address = var.ip
        gateway = "192.168.10.1"
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      keys = split("\n", trimspace(var.ssh_public_key)) # one key per line (owner, CI)
    }
  }

  lifecycle {
    # Same reasoning as the VM module: these only matter at creation, and
    # drift in them must never plan a destroy + recreate.
    ignore_changes = [
      initialization,
      operating_system,
      disk,
    ]
  }
}
