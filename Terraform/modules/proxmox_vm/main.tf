resource "proxmox_vm_qemu" "vm" {
  name        = var.name
  target_node = var.target_node
  clone       = var.clone
  full_clone  = var.full_clone
  vmid        = var.vmid

  cores  = var.cores
  memory = var.memory

  ciuser     = var.ciuser
  cipassword = var.cipassword


  ipconfig0 = "ip=${var.ip},gw=192.168.1.1,nameserver=192.168.1.1"
  sshkeys = var.ssh_public_key



  network {
    id     = 0
    model  = "virtio"   
    bridge = "vmbr0"
  }


  scsihw = "virtio-scsi-pci"

 # PCI passthrough as a block
  dynamic "hostpci" {
    for_each = var.hostpcis
    content {
      host = hostpci.value  # e.g., "0000:01:00.0"
      pcie = true           # enable PCIe
    }
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      slot    = disk.value.slot
      storage = disk.value.storage
      size    = disk.value.size
      type    = disk.value.type 
    }
  }

  lifecycle {
    prevent_destroy = true
  }

}
