variable "vms" {
  type = map(object({
    name     = string
    vmid     = number
    ip       = string           # for reference / provisioner
    cores    = number
    memory   = number
    hostpcis = optional(list(string), [])  # optional PCI passthrough
    disks    = optional(list(object({
      datastore_id = string
      interface    = string
      size         = number
      file_format  = string
      file_id      = string
      iothread     = bool
      discard      = string
    })), [])
  }))
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