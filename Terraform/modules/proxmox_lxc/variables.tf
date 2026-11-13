variable "name" {
  type = string
}

variable "vmid" {
  type = number
}

variable "description" {
  type    = string
  default = ""
}

variable "target_node" {
  type = string
}

variable "template_file_id" {
  type        = string
  description = "LXC template volume, e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ip" {
  type        = string
  description = "Static IP in CIDR form"
}

variable "dns_servers" {
  type = list(string)
}

variable "cores" {
  type = number
}

variable "memory" {
  type        = number
  description = "RAM limit in MB (a cgroup limit, not reserved like VM RAM)"
}

variable "swap" {
  type    = number
  default = 512
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "disk_size" {
  type        = number
  description = "Root disk in GB"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key installed for root"
}

variable "pool_id" {
  type        = string
  description = "Proxmox resource pool the container joins at creation"
  default     = null
}
