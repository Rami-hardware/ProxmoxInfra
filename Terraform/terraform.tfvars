vms = {
  gateway = {
    name       = "gateway-server"
    vmid       = 505
    ip         = "192.168.1.200/24"
    cores      = 2
    memory     = 2048
    balloon    = 1024
    ciuser     = "gateway"
    cipassword = "gateway@123"
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  media = {
    name       = "media-server"
    vmid       = 911
    ip         = "192.168.1.201/24"
    cores      = 3
    memory     = 8192
    balloon    = 4096
    ciuser     = "media"
    cipassword = "media@123"
    hostpcis   = ["0000:03:00.0", "0000:04:00.0"]
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 200
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  monitoring = {
    name       = "monitoring-server"
    vmid       = 511
    ip         = "192.168.1.203/24"
    cores      = 1
    memory     = 2048
    balloon    = 0
    ciuser     = "monitoring"
    cipassword = "monitoring@123"
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  security = {
    name       = "security-server"
    vmid       = 619
    ip         = "192.168.1.202/24"
    cores      = 2
    memory     = 4096
    balloon    = 2048
    ciuser     = "security"
    cipassword = "security@123"
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 50
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  github = {
    name       = "git-k3s-server"
    vmid       = 115
    ip         = "192.168.1.204/24"
    cores      = 2
    memory     = 8192
    balloon    = 4096
    ciuser     = "github"
    cipassword = "github@123"
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }
}
