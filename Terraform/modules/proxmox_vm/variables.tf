variable "name" {
  type = string
}

variable "vmid" {
  type = number
}

variable "ciuser" {
  type = string
}

variable "cipassword" {
  type = string
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
    slot    = string
    storage = string
    size    = string
    type    = string
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
  default = "/home/github-server/.ssh/id_rsa.pub" 
  description = "Path to the SSH public key for cloud-init access"
}

variable "hostpcis" {
  type    = list(string)
  default = []
}