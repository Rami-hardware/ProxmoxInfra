variable "name" {
  type = string
}

variable "vmid" {
  type = number
}

variable "ciuser" {
  type      = string
  default   = ""    # now optional
  description = "Optional: cloud-init user (ignored by bpg/proxmox)"
}

variable "cipassword" {
  type      = string
  default   = ""    # now optional
  description = "Optional: cloud-init password (ignored by bpg/proxmox)"
}

variable "ip" {
  type        = string
  description = "Static IP for the VM"
}


variable "cores" {
  type = number
}

variable "memory" {
  type = number
}

variable "clone" {
  type = string
}

variable "full_clone" {
  type    = bool
  default = false
}

variable "target_node" {
  type = string
}


variable "disks" {
  type = list(object({
    datastore_id = string   # e.g., "local-lvm"
    interface    = string   # e.g., "virtio0" or "scsi0"
    size         = number   # in GB
    file_format  = string   # e.g., "qcow2"
    file_id      = string   # empty string if creating new
    iothread     = bool     # true/false
    discard      = string   # "on" or "off"
  }))
  default = []
}


variable "cloudinit_storage" {
  type    = string
  default = "local-lvm"
}

variable "cloudinit_size" {
  type    = string
  default = "5G"
}

variable "ssh_key_path" {
  type        = string
  default     = "/home/ubuntu/.ssh/id_rsa.pub"
  description = "Path to the SSH public key for cloud-init access"
}
variable "hostpcis" {
  type    = list(string)
  default = []
}

variable "ssh_public_key" {
  description = "Public SSH key for VM access"
  type        = string
}