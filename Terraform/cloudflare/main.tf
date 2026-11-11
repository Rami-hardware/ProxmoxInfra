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

# Zone-level cache rules (one ruleset per zone for this phase).
resource "cloudflare_ruleset" "cache" {
  zone_id = data.cloudflare_zone.this.id
  name    = "Cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # Jellyfin's web bundles are versioned by a ?<hash> query string (part of
      # the cache key), but the origin only sends max-age=14400, so the edge
      # revalidates with the origin every 4 h. Keep them for 30 days at the
      # edge and 7 days in the browser. index.html is not matched.
      description = "Jellyfin web assets: long edge and browser TTL"
      enabled     = true
      expression  = "(http.host eq \"jellyfin.${var.zone_name}\" and starts_with(http.request.uri.path, \"/web/\") and http.request.uri.path.extension in {\"js\" \"css\" \"woff\" \"woff2\"})"
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
