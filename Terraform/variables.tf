variable "vms" {
  type = map(object({
    name       = string
    vmid       = number
    ip         = string
    cores      = number
    memory     = number
    ciuser     = string
    cipassword = string
    hostpcis   = optional(list(string), [])  # optional PCI passthrough
    disks = optional(list(object({
      datastore_id = string  # e.g., "local-lvm"
      interface    = string  # e.g., "virtio0" or "scsi0"
      size         = number  # in GB
      file_format  = string  # e.g., "qcow2"
      file_id      = string  # empty string if creating new
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