provider "proxmox" {
  endpoint = var.pm_api_url
  api_token = var.token
  insecure = true  
}
