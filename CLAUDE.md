# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

All agent rules, commands, conventions and load-bearing quirks live in AGENTS.md (shared with other agents) — keep them there, not here:

@AGENTS.md

## Big Picture (spans multiple files)

**Layers, in order:** Terraform creates the Proxmox VMs → Ansible configures hosts and bootstraps the cluster → ArgoCD deploys apps. Each layer hands off at a clear line — know which one owns what before editing.

| Host (inventory) | IP | Role |
| :--- | :--- | :--- |
| `gateway-server` | .200 | DNS (AdGuard), CrowdSec, nginx reverse proxy for every `*.homelab.lan` URL; K3s worker for `network` ns |
| `media-server` | .201 | K3s worker, `media` ns; Intel Arc GPU passthrough |
| `monitoring-server` | .203 | K3s worker, `monitoring` ns (Prometheus, Grafana, Loki, Tempo, Alertmanager); unbound (fallback DNS upstream) |
| `git-k3s-server` | .204 | K3s control plane + self-hosted GitHub Actions runner + ArgoCD/Image Updater |
| `host-node` | .250 | Proxmox host itself (ZFS, backups) |

**Ansible vs ArgoCD ownership:**
- Ansible (`git-k3s-server.yml` → `k3s_server`, `k3s_apps` roles) owns cluster infra: K3s, Helm releases (cert-manager, ingress-nginx, Istio, ArgoCD + Image Updater), and cluster-wide DaemonSets (node-exporter, Promtail, kube-state-metrics). Changes here need CI / a playbook run.
- ArgoCD owns everything under `Ansbile/argocd-apps/` — push to `main` and it syncs. Image Updater commits `build: automatic update of <ns>` back to `main`; pull before pushing.

**Exposing a service:** app gets a NodePort in its `argocd-apps/` YAML → gateway nginx proxies it via `nginx_services_local` in `group_vars/gateway-vm.yml` → TLS from the internal CA (`homelab-ca-issuer`). New Prometheus targets go in `roles/prometheus/templates/prometheus.yml.j2`; new alerts in `prometheus-rules.yml.j2` with a `runbook_url` to a file in `docs/runbooks/`.

**Branch ↔ ArgoCD:** Application CRs track `targetRevision: main` only — pushing app YAML to `staging`/`development` runs CI but deploys nothing to the cluster.
