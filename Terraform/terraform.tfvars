vms = {
  gateway = {
    name       = "gateway-server"
    vmid       = 505
    ip         = "192.168.1.200/24"
    cores      = 2
    memory     = 1024
    ciuser     = "gateway"
    cipassword = "gateway@123"
    hostpcis = []  # no PCI devices
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "scsi0", storage = "local-lvm", size = "20G", type = "disk" },
    ]
  }

  media = {
    name       = "media-server"
    vmid       = 911
    ip         = "192.168.1.201/24"
    cores      = 2
    memory     = 4096
    ciuser     = "media"
    cipassword = "media@123"
    hostpcis = ["0000:01:00.0", "0000:01:00.1"]  # <-- list of strings
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "ide0", storage = "local-lvm", size = "200G", type = "disk" },
      { slot = "scsi0", storage = "media", size = "9650G", type = "disk" }
    ]
  }

  game = {
    name       = "game-server"
    vmid       = 619
    ip         = "192.168.1.202/24"
    cores      = 4
    memory     = 8124
    ciuser     = "game"
    cipassword = "game@123"
    hostpci    = null
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "ide0", storage = "local-lvm", size = "50G", type = "disk" },
    ]
  }

  monitor = {
    name       = "monitor-server"
    vmid       = 115
    ip         = var.ip_monitor
    cores      = 4
    memory     = 8124
    ciuser     = "monitor"
    cipassword = "monitor@123"
    hostpci    = null
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "scsi0", storage = "local-lvm", size = "20G", type = "disk" },
    ]
  }
}