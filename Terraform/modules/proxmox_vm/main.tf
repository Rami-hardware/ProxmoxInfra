resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.name
  node_name = var.target_node
  vm_id     = var.vmid
  # optional clone block — documented for this resource
  clone {
    vm_id     = 9000   # ID of the template to clone
    node_name = var.target_node   # node where the template lives
    full      = var.full_clone
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

dynamic "disk" {
  for_each = var.disks
  content {
    datastore_id = disk.value.datastore_id
    interface    = disk.value.interface
    size         = disk.value.size
    file_format  = lookup(disk.value, "file_format", null)
    file_id      = lookup(disk.value, "file_id", null)
    iothread     = lookup(disk.value, "iothread", null)
    discard      = lookup(disk.value, "discard", null)
  }
}

initialization {
     ip_config {
         ipv4 {
             address = var.ip
             gateway = "192.168.1.1" 
          }
      }
     user_account { 
         password = var.cipassword
         username = var.ciuser
      }
  }


  network_device {
    bridge = "vmbr0"
  }

  
  lifecycle {
  prevent_destroy = false
}

}
