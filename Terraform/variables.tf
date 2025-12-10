variable "vms" {
  type = map(object({
    name       = string
    vmid       = number
    ip         = string
    cores      = number
    memory     = number
    ciuser     = string
    cipassword = string
    disks = optional(list(object({
      slot    = string
      storage = string
      size    = string
      type    = string
    })))
  }))
}
variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL"
  sensitive   = true
}

variable "pm_user" {
  type        = string
  description = "Proxmox user"
  sensitive   = true
}

variable "pm_password" {
  type        = string
  description = "Proxmox password"
  sensitive   = true
}
variable "ssh_public_key" {
  description = "Public SSH key for VMs"
  type        = string
}