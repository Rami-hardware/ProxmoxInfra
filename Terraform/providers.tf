provider "proxmox" {
  endpoint = var.pm_api_url
  api_token = var.pm_api_token
  insecure = true  
}
