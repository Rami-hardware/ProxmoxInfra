vms = {
  gateway = {
    name       = "gateway-server"
    vmid       = 505
    ip         = "192.168.1.200/24"
    cores      = 2
    memory     = 2048
    ciuser     = "gateway"
    cipassword = "gateway@123"
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "qcow2"
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
    memory     = 4096
    ciuser     = "media"
    cipassword = "media@123"
    hostpcis   = ["0000:01:00.0", "0000:01:00.1"]
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 200
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
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
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 50
        file_format  = "qcow2"
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
    cores      = 2
    memory     = 2048
    ciuser     = "monitoring"
    cipassword = "monitoring@123"
    hostpci    = null
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  github = {
    name       = "github-server"
    vmid       = 115
    ip         = "192.168.1.204/24"
    cores      = 4
    memory     = 6144
    ciuser     = "github"
    cipassword = "github@123"
    hostpci    = null
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 5
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      },
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 20
        file_format  = "qcow2"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }

  dev = {
    name       = "dev-server"
    vmid       = 223
    ip         = "192.168.1.205/24"
    cores      = 2
    memory     = 1024
    ciuser     = "dev"
    cipassword = "dev@123"
    hostpci    = null
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 10
        file_format  = "raw"
        file_id      = ""
        iothread     = true
        discard      = "on"
      }
    ]
  }
}
