# Homelab Infrastructure

A self-hosted homelab on one Proxmox host. Terraform creates the VMs and the
CI runner containers, Ansible configures the hosts and bootstraps a K3s
cluster, and ArgoCD deploys the apps from this repo. Everything is
monitored with Prometheus, Loki and Tempo, and every alert links to a runbook.
Changes ship through GitHub Actions: tested on `development`, deployed to the
real hosts as a canary from `staging`, then promoted to `main` (production)
after a smoke test and an approval.

> Agent and contributor rules (conventions, load-bearing quirks) live in
> [AGENTS.md](AGENTS.md); the cross-file overview is in [CLAUDE.md](CLAUDE.md).
> Disaster recovery: [docs/rebuild.md](docs/rebuild.md). Runbooks:
> [docs/runbooks/](docs/runbooks/README.md).

---

## Architecture

```text
            Terraform (Proxmox VMs + LXCs, Cloudflare)
                              │
   ┌──────────────────────────┴──────────────────────────┐
   │ Proxmox VE host  rami / 192.168.10.250  (ZFS, vzdump) │
   │                                                     │
   │  gateway .200   media .201   monitoring .203   git-k3s .204   ci-runner-1/2/3 .205-.207
   │  K3s agent      K3s agent    K3s agent         K3s server     LXC, GitHub Actions
   └─────────────────────────────────────────────────────┘
                              │ Ansible (roles per host)
                              ▼
        K3s cluster ── ArgoCD syncs Ansbile/argocd-apps/ from main
                   └── Image Updater commits new image digests to main
```

Three layers, each with a clear owner:

| Layer | Owns | Changed by |
| :--- | :--- | :--- |
| **Terraform** (`Terraform/`) | Proxmox VMs and LXCs; Cloudflare zone settings, cache rules, tunnel | CI applies on `main` after approval (destroy/replace is blocked) |
| **Ansible** (`Ansbile/`, 19 roles) | Host config, K3s, Helm releases (cert-manager, MetalLB, ingress-nginx, Istio, ArgoCD, Image Updater, Homarr), cluster DaemonSets, Ingress routes | CI, only the roles whose files changed |
| **ArgoCD** (`Ansbile/argocd-apps/`) | The apps in the `media`, `monitoring`, `network` namespaces | Push to `main`; ArgoCD syncs (self-heal + prune) |

### Hosts

| Host | IP | vCPU / RAM | Role |
| :--- | :--- | :--- | :--- |
| `host-node` (Proxmox) | 192.168.10.250 | i5-10400F, 33.6 GB | Hypervisor, ZFS `tank`, nightly vzdump backups |
| `gateway-server` | 192.168.10.200 | 2 / 2 GB | AdGuard Home (primary DNS, systemd), K3s agent (`network`) |
| `media-server` | 192.168.10.201 | 6 / 7 GB | K3s agent (`media`), Intel Arc GPU passthrough |
| `monitoring-server` | 192.168.10.203 | 2 / 8 GB | K3s agent (`monitoring`), Unbound (secondary DNS), ingress-nginx replica |
| `git-k3s-server` | 192.168.10.204 | 3 / 7 GB | K3s control plane (sqlite), ArgoCD, Istio, Tempo, ingress-nginx replica |
| `ci-runner-1/2/3` | 192.168.10.205-207 | 2 / 2 GB each | Unprivileged LXCs, two GitHub Actions runners each (6 parallel jobs) |

VM 100 is the owner's macOS test VM: not managed by Terraform, excluded from
backups (it shares media's GPU), never started while media runs.

---

## Services

All `*.homelab.lan` names resolve through AdGuard/Unbound to ingress-nginx
(MetalLB `192.168.10.210`) with TLS from the internal CA
(`http://ca.homelab.lan/ca.crt` — trust it once per device). Public names
under `darkestserver.com` come in through a Cloudflare Tunnel.

### Media — `media` namespace (media-server)

| App | URL | Notes |
| :--- | :--- | :--- |
| Jellyfin | <https://jellyfin.homelab.lan> · public | Intel Arc VAAPI transcoding via the GPU device plugin (not privileged) |
| Seerr | <https://seerr.homelab.lan> · public | Media requests |
| Sonarr / Radarr | <https://sonarr.homelab.lan> / <https://radarr.homelab.lan> | TV / movie automation |
| Prowlarr | <https://prowlarr.homelab.lan> | Indexers |
| Bazarr | <https://bazarr.homelab.lan> | Subtitles (GPU ffmpeg for sync) |
| qBittorrent | <https://qbittorrent.homelab.lan> | BitTorrent port 6881 open to the internet |
| Tracearr | <https://tracearr.homelab.lan> | Playback tracking (TimescaleDB pg18 + Redis 8) |
| Homarr | <https://homarr.homelab.lan> | Dashboard (Helm, installed by Ansible) |
| FlareSolverr, Scraparr | — | Cloudflare challenge solver; *arr metrics exporter |

### Monitoring — `monitoring` namespace (monitoring-server)

| App | URL | Notes |
| :--- | :--- | :--- |
| Grafana | <https://grafana.homelab.lan> | Dashboards (login required); no alert rules live here |
| Prometheus | <https://prometheus.homelab.lan> | 15d / 12 GB retention, LAN only |
| Alertmanager | <https://alertmanager.homelab.lan> | Routes to alert-forwarder → Discord; heartbeat to healthchecks.io; LAN only |
| Loki | `:3100` | Logs, 30d retention; ruler remote-writes `log:*` metrics to Prometheus |
| alert-forwarder | `:30302` | Own Node.js app (`Ansbile/apps/alert-forwarder`), Alertmanager → Discord |
| Exporters | — | blackbox (local, public, DNS), speedtest, qBittorrent, Intel GPU |

### Cluster and network

| Service | Where | Notes |
| :--- | :--- | :--- |
| AdGuard Home | gateway, systemd | Primary DNS (:53), UI <https://adguard.homelab.lan> |
| Unbound | monitoring, systemd | Secondary DNS, full recursion + the same local names |
| ArgoCD | <https://argocd.homelab.lan> | GitOps; login `admin`, password in `argocd-initial-admin-secret` |
| Tempo | <https://tempo.homelab.lan> | Traces from Istio and ingress-nginx, 7d; LAN only |
| Proxmox UI | <https://server.homelab.lan> | Proxied to `192.168.10.250:8006` |
| ingress-nginx | git-k3s + monitoring | hostNetwork, one replica per node, MetalLB VIP `.210` |
| Istio ambient | `media`, `monitoring`, `network` | ztunnel mTLS, waypoint + AuthorizationPolicies in `media` |
| cert-manager | — | Internal CA issuer + Let's Encrypt wildcard (Cloudflare DNS-01) |

---

## Security model

- **Network policy**: every mesh namespace is default-deny ingress. The LAN may
  reach app pods; the no-login admin APIs (Prometheus, Alertmanager, Loki,
  alert-forwarder, and the Prometheus/Alertmanager/Tempo ingresses) accept the
  home LAN `192.168.10.0/24` only — never the tunnel or a VPN range. `media`
  egress cannot reach the LAN.
- **SSH**: key-only everywhere (`roles/common`). Separate keys per consumer
  (`roles/ssh_access`): the owner's, and CI's — which is also ArgoCD's GitHub
  deploy key. Host keys are pinned in `.github/ssh_known_hosts`.
- **CI**: actions pinned to commit SHAs, read-only `GITHUB_TOKEN` by default,
  each secret only in the job that uses it, no `pull_request` trigger (public
  repo, LAN runners).
- **Secrets**: Ansible Vault (`group_vars/all/vault.yml`) and GitHub secrets;
  GitHub secret scanning + push protection. Terraform verifies the Proxmox API
  certificate (the runners trust the PVE cluster CA).
- **Containers**: no privileged app pods except the cluster agents that need
  host access (node-exporter); the GPU is handed out by the Intel device plugin.

---

## CI/CD

Runs on push to `development`, `staging` and `main`, and monthly on `main`
(full redeploy). Only what changed runs: `.github/scripts/detect-changed-hosts.sh`
diffs against the branch's last green run and maps each changed file to the
hosts and roles (`ansible-playbook --tags`) that use it.

```text
Detect Changed Hosts ─┬─ Build image (alert-forwarder, only when its code changed)
                      └─ Testing: Terraform fmt/validate, syntax check + ansible-lint
                                  of what changed, gateway --check (development)
Deploy (staging/main):
  Terraform plan ─► Approval (Production: owner) ─► Terraform apply (main, code changes only)
     ─► gateway | monitoring | media | git-k3s | host-node | ci-runners   (in parallel,
        each silences only its own host's warning alerts while it runs)
     ─► Cloudflare (when Terraform/cloudflare changed)
     ─► Smoke test: nodes, workloads, ArgoCD health, every ingress, DNS, monitoring
        APIs, deployed hosts' scrape targets
Notify ─► Discord
```

| Branch | What happens |
| :--- | :--- |
| `development` | Tested, never deployed. Dependabot/Renovate PRs land here. |
| `staging` | Canary: deploys its changes to the real hosts; the smoke test is the verdict. |
| `main` | Production. Moved only by **Promote staging → main** (requires a green staging run), then waits for the owner's approval. |

Supporting workflows: `checks.yml` (server-side dry run of `argocd-apps/` and
the alertops-mcp tests), `promote.yml`, `runner-health.yml` (every 15 min,
Discord on change), `runner-retry.yml` (re-runs jobs lost with their runner).

### Keeping versions current

| What | How |
| :--- | :--- |
| App images in `argocd-apps/` | **ArgoCD Image Updater** (v0.12.2), every ~2 min, commits digests to `main`. Stateful apps follow one major only (Prometheus `v3`, Loki `3`, Grafana `13.x`, Jellyfin `12`, Redis `8-alpine`, TimescaleDB `pg18`). |
| k3s, Helm charts, Istio, Ansible-pinned images, host tools, Terraform, CI Python tools | **Renovate** (`renovate.json`): weekly PRs to `development`; k3s moves one minor at a time. Each pin has a `# renovate:` comment. |
| GitHub Actions, alert-forwarder base image and npm | **Dependabot** (`.github/dependabot.yml`), weekly, LTS Node only |

---

## Observability

- **Metrics**: Prometheus scrapes node-exporter on every VM, runner and the
  Proxmox host, kubelet/cAdvisor, kube-state-metrics, CoreDNS, ingress-nginx,
  Istio (mesh + ztunnel), ArgoCD, cert-manager, Tempo, Alloy, cloudflared,
  ZFS, SMART and PVE exporters, the app exporters, and blackbox probes of every
  local URL, the public URLs and both DNS servers (28 scrape jobs).
- **Logs**: Grafana Alloy (DaemonSet) ships pod and system logs to Loki.
  Log-based alerts are Prometheus rules over Loki's `log:*` recording rules.
- **Traces**: Istio ambient + ingress-nginx → Tempo (100% sampling).
- **Alerts**: 151 rules in `Ansbile/roles/prometheus/templates/prometheus-rules.yml.j2`,
  each with a `runbook_url`. SLOs (99.5% sites, 99.9% DNS, 14-day window) use
  multi-window burn-rate alerts. A Watchdog heartbeat goes to healthchecks.io,
  which emails if monitoring itself dies.
- **Auto-remediation (optional)**: `tools/alertops-mcp` is an MCP server that
  lets the `alert-fixer` agent investigate, apply allowlisted fixes, verify and
  report to Discord (rate limits, cooldowns, kill switch).

---

## Backups and recovery

- Nightly vzdump of all VMs to `tank/backup` on the host (7 daily + 4 weekly).
- Nightly consistent snapshot of the k3s datastore inside git-k3s
  (`/var/backups/k3s`, 7 kept), alerted on if stale.
- Terraform state is committed to git; Cloudflare state lives in a K3s Secret.
- Full rebuild procedure: [docs/rebuild.md](docs/rebuild.md).

---

## Repository layout

```text
Terraform/                Proxmox VMs/LXCs (terraform.tfvars), Cloudflare (Terraform/cloudflare)
Ansbile/                  (spelled this way on purpose)
  inventory.ini           hosts and their Ansible users
  <host>.yml              one playbook per host
  group_vars/             per-host vars; all/vault.yml is fully encrypted
  roles/                  19 roles (k3s_apps holds the cluster add-ons, one task file each)
  argocd-apps/            ArgoCD Applications (*-app.yaml) and the media/monitoring/network apps
  apps/alert-forwarder/   Node.js app + Helm chart
.github/                  workflows, composite actions, scripts, dependabot.yml
renovate.json             Renovate config
docs/                     rebuild.md, incident template, runbooks/
tools/alertops-mcp/       alert investigation/remediation MCP server
```

---

## Technologies

| Category | Tools |
| :--- | :--- |
| Virtualization | Proxmox VE, ZFS |
| IaC / config | Terraform (`bpg/proxmox`, `cloudflare`), Ansible |
| Kubernetes | K3s, Helm, ArgoCD + Image Updater, MetalLB, ingress-nginx, cert-manager |
| Service mesh | Istio ambient (ztunnel, waypoint), Tempo |
| CI/CD | GitHub Actions on self-hosted LXC runners, Dependabot, Renovate |
| Observability | Prometheus, Alertmanager, Grafana, Loki, Grafana Alloy, blackbox exporter |
| DNS / edge | AdGuard Home, Unbound, Cloudflare (tunnel, DNS) |
| Media | Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, Seerr, Tracearr, Homarr |

---

## Author

Rami Osama Dannah — DevOps Engineer
