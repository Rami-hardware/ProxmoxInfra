# Cloudflare Tunnel: public hostnames reach the cluster through an outbound
# connection from cloudflared (namespace cloudflared, deployed by the k3s_apps
# role), so no inbound port is open on the router and the home IP is not in
# public DNS. CI stores the connector token as the cloudflared-token Secret.

locals {
  # Public names served through the tunnel (same list as
  # local_dns_public_names in Ansbile/group_vars/all/local_dns.yml).
  tunnel_hostnames = ["jellyfin", "seerr", "adguard"]

  # ingress-nginx (hostNetwork on git + monitoring) behind its ClusterIP.
  # The Let's Encrypt wildcard is its default certificate, so TLS to the
  # origin is verified against the real hostname.
  tunnel_origin = "https://ingress-nginx-controller.ingress-nginx.svc.cluster.local:443"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = data.cloudflare_zone.this.account.id
  name       = "homelab"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = data.cloudflare_zone.this.account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config = {
    ingress = concat(
      [
        for name in local.tunnel_hostnames : {
          hostname = "${name}.${var.zone_name}"
          service  = local.tunnel_origin
          origin_request = {
            origin_server_name = "${name}.${var.zone_name}"
            http2_origin       = true
          }
        }
      ],
      # Anything else that reaches the tunnel gets a 404.
      [{ service = "http_status:404" }]
    )
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  account_id = data.cloudflare_zone.this.account.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
  sensitive = true
}
