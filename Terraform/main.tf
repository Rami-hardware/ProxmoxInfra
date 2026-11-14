module "proxmox_vms" {
  source         = "./modules/proxmox_vm"
  for_each       = var.vms
  name           = each.value.name
  target_node    = "rami"
  clone_vm_id    = 9000 # ubuntu-24.04-cloud-init-template
  full_clone     = true
  vmid           = each.value.vmid
  ciuser         = each.value.ciuser
  cipassword     = each.value.cipassword
  ip             = each.value.ip
  cores          = each.value.cores
  memory         = each.value.memory
  balloon        = each.value.balloon
  hostpcis       = lookup(each.value, "hostpcis", [])
  disks          = lookup(each.value, "disks", [])
  ssh_public_key = var.ssh_public_key
}

module "proxmox_containers" {
  source           = "./modules/proxmox_lxc"
  for_each         = var.containers
  name             = each.value.name
  vmid             = each.value.vmid
  description      = each.value.description
  target_node      = "rami"
  template_file_id = var.lxc_template_file_id
  ip               = each.value.ip
  dns_servers      = var.lxc_dns_servers
  cores            = each.value.cores
  memory           = each.value.memory
  disk_size        = each.value.disk_size
  ssh_public_key   = var.ssh_public_key
}

# The monitoring VM (vmid 511) was renamed from the "monitor" key. Without
# this, the plan destroys the live VM and creates a new one.
moved {
  from = module.proxmox_vms["monitor"]
  to   = module.proxmox_vms["monitoring"]
}
