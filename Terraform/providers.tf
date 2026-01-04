provider "proxmox" {
  endpoint = var.pm_api_url      # e.g., "https://proxmox.example.com:8006/api2/json"
  username = var.pm_user         # e.g., "root@pam"
  password = var.pm_password
  insecure = true                # set to false if you have proper TLS
}
