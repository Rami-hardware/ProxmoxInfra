variable "vms" {
  type = map(object({
    name       = string
    vmid       = number
    ip         = string
    cores      = number
    memory     = number
    balloon    = optional(number, 0) # min balloon RAM in MB; 0 = disabled
    ciuser     = string
    cipassword = string
    hostpcis   = optional(list(string), []) # optional PCI passthrough
    disks = optional(list(object({
      datastore_id = string # e.g., "local-lvm"
      interface    = string # e.g., "virtio0" or "scsi0"
      size         = number # in GB
      file_format  = string # e.g., "qcow2"
      file_id      = string # empty string if creating new
      iothread     = bool
      discard      = string
    })), [])
  }))
}

# LXC containers (currently the GitHub Actions runners). Map keys are state
# addresses, same as vms: renaming one destroys the container.
variable "containers" {
  type = map(object({
    name        = string
    vmid        = number
    description = optional(string, "")
    ip          = string
    cores       = number
    memory      = number
    disk_size   = number
  }))
  default = {}
}

# Download once on the Proxmox host before the first apply:
#   pveam update && pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
variable "lxc_template_file_id" {
  type    = string
  default = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

# AdGuard on the gateway first, unbound on monitoring as the fallback.
variable "lxc_dns_servers" {
  type    = list(string)
  default = ["192.168.10.200", "192.168.10.203"]
}

variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL"
  sensitive   = true
}

variable "pm_api_token" {
  type        = string
  description = "Proxmox API token (user@realm!tokenid=secret)"
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Public SSH key for VMs"
  type        = string
}