terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
  }

  # State lives in a Secret (tfstate-default-cloudflare) in the terraform
  # namespace on the K3s cluster, with a Lease for locking. The CI runner runs
  # on the control-plane node and reads the local kubeconfig.
  backend "kubernetes" {
    secret_suffix = "cloudflare"
    namespace     = "terraform"
    config_path   = "/etc/rancher/k3s/k3s.yaml"
  }
}
