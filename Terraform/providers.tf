provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = var.pm_api_token
  # TLS is verified: the PVE certificate is signed by the cluster CA, which
  # roles/ci_runner installs on the runners (files/pve-root-ca.crt). For a
  # manual run elsewhere, trust that CA too (or /etc/pve/pve-root-ca.pem).
}
