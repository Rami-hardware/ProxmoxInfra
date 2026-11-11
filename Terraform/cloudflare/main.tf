data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

# Saves one round trip to the edge on resumed TLS connections. Only idempotent
# requests (GET/HEAD) are sent as early data.
resource "cloudflare_zone_setting" "zero_rtt" {
  zone_id    = data.cloudflare_zone.this.id
  setting_id = "0rtt"
  value      = "on"
}

locals {
  jellyfin_host = "jellyfin.${var.zone_name}"
  # Jellyfin's web bundles: versioned by a ?<hash> query string (part of the
  # cache key). index.html is not matched.
  jellyfin_web_assets = "starts_with(http.request.uri.path, \"/web/\") and http.request.uri.path.extension in {\"js\" \"css\" \"woff\" \"woff2\"}"
}

# The zone's single ruleset for this phase. It existed before this module
# (created in the dashboard as "default"), hence the import block below.
resource "cloudflare_ruleset" "cache" {
  zone_id = data.cloudflare_zone.this.id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # Video streams (.mp4 is a default cached extension), the API and
      # per-user images never go into the edge cache. Replaces the dashboard
      # rule, whose full_uri pattern lacked the scheme and never matched.
      description = "Jellyfin: bypass cache except web assets"
      enabled     = true
      expression  = "(http.host eq \"${local.jellyfin_host}\" and not (${local.jellyfin_web_assets}))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    },
    {
      # The origin only sends max-age=14400, so the edge revalidated these
      # every 4 h. Keep them 30 days at the edge and 7 days in the browser.
      description = "Jellyfin web assets: long edge and browser TTL"
      enabled     = true
      expression  = "(http.host eq \"${local.jellyfin_host}\" and ${local.jellyfin_web_assets})"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 2592000
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 604800
        }
      }
    }
  ]
}

import {
  to = cloudflare_ruleset.cache
  id = "zones/46593646510004b325d04d011dcc49df/c3f2031260ef42fa99bb4aa88e0e9f9b"
}
