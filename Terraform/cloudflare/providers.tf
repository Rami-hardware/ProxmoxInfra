# Authenticates with CLOUDFLARE_API_TOKEN from the environment (CI passes the
# CF_DNS_API_TOKEN secret, scoped to the darkestserver.com zone).
provider "cloudflare" {}
