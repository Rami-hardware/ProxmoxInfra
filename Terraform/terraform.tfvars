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
      { slot = "scsi0", storage = "local-lvm", size = "200G", type = "disk" , boot = true},
      { slot = "scsi1", storage = "media", size = "9650G", type = "disk" }
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
    vmid       = 511
    ip         = "192.168.1.203/24"
    cores      = 4
    memory     = 1024
    ciuser     = "monitor"
    cipassword = "monitor@123"
    hostpci    = null
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "scsi0", storage = "local-lvm", size = "20G", type = "disk" },
    ]
  }

  github = {
    name       = "github-server"
    vmid       = 115
    ip         = "192.168.1.204/24"
    cores      = 4
    memory     = 2048
    ciuser     = "github"
    cipassword = "github@123"
    hostpci    = null
    disks = [
      { slot = "ide2", storage = "local-lvm", size = "5G", type = "cloudinit" },
      { slot = "scsi0", storage = "local-lvm", size = "20G", type = "disk" },
    ]
  }
}