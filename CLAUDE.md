# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

All agent rules, commands, conventions and load-bearing quirks live in AGENTS.md (shared with other agents) — keep them there, not here:

@AGENTS.md

## Big Picture (spans multiple files)

**Layers, in order:** Terraform creates the Proxmox VMs → Ansible configures hosts and bootstraps the cluster → ArgoCD deploys apps. Each layer hands off at a clear line — know which one owns what before editing.

| Host (inventory) | IP | Role |
| :--- | :--- | :--- |
| `gateway-server` | .200 | DNS (AdGuard, systemd); K3s worker for `network` ns |
| `media-server` | .201 | K3s worker, `media` ns; Intel Arc GPU passthrough |
| `monitoring-server` | .203 | K3s worker, `monitoring` ns (Prometheus, Grafana, Loki, Alertmanager); ingress-nginx replica; unbound (secondary DNS) |
| `git-k3s-server` | .204 | K3s control plane + self-hosted GitHub Actions runner + ArgoCD/Image Updater; ingress-nginx replica; Tempo + istiod (`istio-system`) |
| `ci-runner-1` / `-2` / `-3` | .205 / .206 / .207 | Unprivileged LXCs (Terraform `containers`, vmid 205–207): GitHub Actions runners, label `lxc`, no Docker (nesting only) |
| `host-node` | .250 | Proxmox host itself (ZFS, backups) |

**Ansible vs ArgoCD ownership:**
- Ansible (`git-k3s-server.yml` → `k3s_server`, `k3s_apps` roles) owns cluster infra: K3s, Helm releases (cert-manager, ingress-nginx, Istio, ArgoCD + Image Updater), and cluster-wide DaemonSets (node-exporter, Grafana Alloy, kube-state-metrics). Changes here need CI / a playbook run.
- ArgoCD owns everything under `Ansbile/argocd-apps/` — push to `main` and it syncs. Image Updater commits `build: automatic update of <ns>` back to `main`; pull before pushing.

**Exposing a service:** app gets a Service in its `argocd-apps/` YAML → add it to `nginx_services_local` in `group_vars/gateway-vm.yml` → the `nginx_config` role renders an Ingress for ingress-nginx (MetalLB `192.168.10.210`, one replica each on git and monitoring) pointing at that Service, TLS from the internal CA (`homelab-ca-issuer`), plus an AdGuard/Unbound name in `group_vars/all/local_dns.yml`. New Prometheus targets go in `prometheus_scrape_jobs` (`group_vars/monitoring-vm.yml`); new alerts in `roles/prometheus/templates/prometheus-rules.yml.j2` with a `runbook_url` to a file in `docs/runbooks/`.

**Mesh and network policy:** `media`, `monitoring`, `network` run in Istio ambient mode (ztunnel mTLS; `media` has a waypoint). Ingress NetworkPolicies come from `argocd-apps/components/mesh-network-policy`; per-Service caller allow lists for `media` are in `argocd-apps/media/authorization-policy.yaml`. A new app-to-app call needs the caller's ServiceAccount added there, and apps must call each other by Service name, not node IP.

**Branch ↔ ArgoCD:** Application CRs track `targetRevision: main` only — pushing app YAML to `staging`/`development` runs CI but deploys nothing to the cluster.
