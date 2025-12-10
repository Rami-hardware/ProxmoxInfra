module "proxmox_vms" {
  source   = "./modules/proxmox_vm"
  for_each = var.vms

  name         = each.value.name
  target_node  = "rami"
  clone        = "ubuntu-24.04-cloud-init-template"
  full_clone   = true
  vmid         = each.value.vmid
  ciuser       = each.value.ciuser
  cipassword   = each.value.cipassword
  ip           = each.value.ip
  cores        = each.value.cores
  memory       = each.value.memory
  hostpcis       = lookup(each.value, "hostpcis", [])
  disks        = lookup(each.value, "disks", [])
  ssh_public_key = var.ssh_public_key
}
