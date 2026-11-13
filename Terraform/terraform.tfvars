vms = {
  gateway = {
    name       = "gateway-server"
    vmid       = 505
    ip         = "192.168.10.200/24"
    cores      = 1
    memory     = 2048
    ciuser     = "gateway"
    cipassword = ""
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
    ip         = "192.168.10.201/24"
    cores      = 6
    memory     = 7168 # was 10240; 7d peak use 5.4 GB. GPU passthrough pins all of it, so this frees 3 GB on the host
    ciuser     = "media"
    cipassword = ""
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
    ip         = "192.168.10.203/24"
    cores      = 1
    memory     = 8192
    ciuser     = "monitoring"
    cipassword = ""
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        size         = 100
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
    ip         = "192.168.10.204/24"
    cores      = 3
    memory     = 7168
    ciuser     = "github"
    cipassword = ""
    hostpcis   = []
    disks = [
      {
        datastore_id = "local-lvm"
        interface    = "virtio0"
        size         = 20
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

# GitHub Actions runners (Ansible: ci-runners.yml). 2 GB is a cgroup limit,
# not reserved; idle use is a few hundred MB.
containers = {
  ci_runner_1 = {
    name        = "ci-runner-1"
    vmid        = 205
    description = "GitHub Actions runner (managed by Terraform + Ansible ci-runners.yml)"
    ip          = "192.168.10.205/24"
    cores       = 2
    memory      = 2048
    disk_size   = 25
  }
  ci_runner_2 = {
    name        = "ci-runner-2"
    vmid        = 206
    description = "GitHub Actions runner (managed by Terraform + Ansible ci-runners.yml)"
    ip          = "192.168.10.206/24"
    cores       = 2
    memory      = 2048
    disk_size   = 25
  }
}
