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

variable "ip_gateway" {
  type        = string
  description = "Ip_gateway"
  sensitive   = true
}

variable "ip_gateway" {
  type        = string
  description = "Gateway VM IP address"
}

variable "ip_media" {
  type        = string
  description = "Media VM IP address"
}

variable "ip_game" {
  type        = string
  description = "Game VM IP address"
}

variable "ip_monitor" {
  type        = string
  description = "Monitor VM IP address"
}

