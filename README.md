# Homelab Infrastructure

A fully automated homelab running on Proxmox, provisioned with Terraform, configured with Ansible, deployed via GitOps with ArgoCD, and monitored end-to-end with Prometheus, Grafana, and Loki.

---

## Architecture

### Physical Host

- **Proxmox VE** on bare metal (`192.168.10.250`)
- Intel Arc GPU passthrough to media VM
- ZFS storage with custom exporter

### Virtual Machines

| VM                | IP            | Cores | RAM  | Role                                      |
| :---------------- | :------------ | :---- | :--- | :---------------------------------------- |
| gateway-server    | 192.168.10.200 | 1     | 3 GB | DNS (AdGuard Home, systemd)               |
| media-server      | 192.168.10.201 | 6     | 10 GB | Media stack — K3s worker                 |
| monitoring-server | 192.168.10.203 | 1     | 8 GB | Observability stack — K3s worker          |
| git-k3s-server    | 192.168.10.204 | 3     | 7 GB | GitHub Actions runner + K3s control plane |
| VM 100 (macOS)    | — | — | 16 GB cfg | Owner's test VM — stopped, not Terraform-managed, excluded from backups |

---

## GitOps with ArgoCD

App deployment is split across two mechanisms:

- **Ansible** bootstraps the cluster itself — K3s, Helm repos, cert-manager, ingress-nginx, Istio, ArgoCD, ArgoCD Image Updater, and cluster-wide DaemonSets (node-exporter, Grafana Alloy, kube-state-metrics).
- **ArgoCD** owns app deployment from here on. Three `Application` resources (`media`, `monitoring`, `network`) auto-sync from `Ansbile/argocd-apps/<name>/` on the `main` branch — editing an app means editing its YAML under `argocd-apps/`, committing, and pushing; ArgoCD picks it up automatically (self-heal + prune enabled, no manual `kubectl apply` needed).

### ArgoCD Image Updater

Tracks the `:latest` (or `:rolling`) tag digest for every app image on a 2-minute poll. When upstream pushes a new image, Image Updater writes a `.argocd-source-<app>.yaml` override into the app's `argocd-apps/` directory and pushes the commit directly to `main` over SSH (deploy key with write access) — ArgoCD then syncs the change automatically. Fully hands-off container updates, no Watchtower needed.

- Pinned to Image Updater **v0.12.2** (last annotation-based release before the v1.x CRD rewrite)
- Each `Application`'s image list + `digest` update strategy is set via `argocd-image-updater.argoproj.io/*` annotations
- Write-back requires each app directory to be a Kustomize base (`kustomization.yaml` with an `images:` block) — plain manifest directories aren't supported for git write-back

### ArgoCD UI

`https://argocd.homelab.lan` — proxied through the gateway's nginx (`nginx_services_local` in `group_vars/gateway-vm.yml`) to ArgoCD's in-cluster NodePort. Login `admin`, password from:

```bash
k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

## Services

### Media (192.168.10.201) — K3s worker, namespace: `media` — ArgoCD-managed

| App          | URL                               | Port | Notes                                         |
| :----------- | :-------------------------------- | :--- | :-------------------------------------------- |
| Jellyfin     | <https://jellyfin.homelab.lan>    | 8096 | Intel Arc GPU transcoding (VAAPI)             |
| Radarr       | <https://radarr.homelab.lan>      | 7878 | Movie automation                              |
| Sonarr       | <https://sonarr.homelab.lan>      | 8989 | TV automation                                 |
| Bazarr       | <https://bazarr.homelab.lan>      | 6767 | Subtitle automation (GPU-accelerated ffmpeg)  |
| Seerr        | <https://seerr.homelab.lan>       | 5055 | Media request management                      |
| qBittorrent  | <https://qbittorrent.homelab.lan> | 8080 | Torrent client — BT port 6881 TCP/UDP         |
| Prowlarr     | <https://prowlarr.homelab.lan>    | 9696 | Indexer management                            |
| FlareSolverr | —                                 | 8191 | Cloudflare bypass (stateless, Chromium-based) |
| Scraparr     | —                                 | 7100 | Prometheus metrics exporter for arr apps      |

### Monitoring (192.168.10.203) — K3s worker, namespace: `monitoring` — ArgoCD-managed

| App                  | URL                                | Port  | Notes                              |
| :------------------- | :--------------------------------- | :---- | :--------------------------------- |
| Grafana              | <https://grafana.homelab.lan>      | 3000  | Dashboards (home: Homelab — Overview) |
| Prometheus           | <https://prometheus.homelab.lan>   | 9090  | Metrics collection, 30d retention  |
| Loki                 | —                                  | 3100  | Log aggregation                    |
| Alertmanager         | <https://alertmanager.homelab.lan> | 9093  | Alert routing                      |
| Speedtest Exporter   | —                                  | 9798  | ISP bandwidth tracking             |
| qBittorrent Exporter | —                                  | 17871 | qBittorrent metrics for Prometheus |
| Intel GPU Exporter   | —                                  | 8082  | Arc GPU utilization metrics        |

AdGuard Home runs on the gateway itself as a **pinned systemd service** (`adguard` role, binary at `/opt/adguardhome`, DNS on :53, UI on 8081) — it is the network's authoritative DNS and the K3s pod-DNS upstream. The `adguard-home` pod in the `network` namespace (hostNetwork) serves the proxied UI; DNS liveness is now covered by the `blackbox-dns` probe + `AdGuardDNSDown` alert instead.

### Network (192.168.10.200) — K3s worker, namespace: `network` — ArgoCD-managed

| App     | URL                           | Port | Notes                           |
| :------ | :---------------------------- | :--- | :------------------------------ |
| AdGuard | <https://adguard.homelab.lan> | 8081 | DNS + ad blocking (hostNetwork) |

Gateway also runs: **AdGuard Home** (systemd service — DNS :53, UI :8081; see the `adguard` role). TLS termination for `*.homelab.lan` / `*.darkestserver.com` happens in-cluster (ingress-nginx + the certs/ingress resources the `nginx_config` role deploys into K3s), not via a gateway nginx container.

### Git / K3s (192.168.10.204)

- **K3s control plane** — Kubernetes API server
- **Docker** — host daemon used by the CI runner for image builds
- **GitHub Actions self-hosted runner** — executes CI/CD pipeline
- **ArgoCD + ArgoCD Image Updater** — GitOps sync + auto image updates
- **cert-manager** — TLS via internal CA (`homelab-ca-issuer`)
- **ingress-nginx** — Kubernetes ingress controller (Helm-managed, LoadBalancer at `192.168.10.210`)
- **Istio** (`istio-base` + `istiod` + `istio-cni` + `ztunnel`) — ambient service mesh (no sidecars) on `media`, `monitoring`, `network`: mTLS between pods, a waypoint in `media` for L7 metrics and traces to Tempo
- **kube-state-metrics** — Kubernetes object metadata exported to Prometheus

### Cluster-wide DaemonSets

| Component        | Nodes                                      | Description                            |
| :--------------- | :----------------------------------------- | :------------------------------------- |
| node-exporter    | media, monitoring, git-k3s-server, gateway | Host-level CPU / memory / disk metrics |
| Grafana Alloy    | media, monitoring, git-k3s-server, gateway | Log shipping to Loki                   |
| kubelet-cAdvisor | media, monitoring, git-k3s-server          | Container metrics via kubelet API      |

---

## Infrastructure as Code

### Terraform

- Provider: `bpg/proxmox`
- All VMs defined as a `map(object)` in `terraform.tfvars` — add/change a VM by editing one block
- Module at `modules/proxmox_vm/` handles all VM resources
- `lifecycle.ignore_changes` covers `disk`, `initialization`, `clone`, `hostpci`, `cpu`
- State tracked per VMID — map keys must never be renamed (would destroy the VM)
- `parallelism=1` required on self-hosted runner to avoid Proxmox API race conditions
- VM apply is currently commented out in CI — plan runs and blocks on destroy/replace, apply is manual

### Ansible

- All modules use FQCN (`ansible.builtin.*`, `community.general.*`)
- All configs rendered from Jinja2 templates — no inline hardcoded content
- IPs reference `hostvars[host]['ansible_host']` from inventory — single source of truth
- Secrets stored in Ansible Vault
- Role variable naming follows `<role_name>_` prefix convention
- Owns cluster bootstrap (K3s, Helm-based infra, DaemonSets) — no longer owns app rollout for `media`/`monitoring`/`network` namespaces, see [GitOps with ArgoCD](#gitops-with-argocd)

### Cluster workloads owned by Ansible

Apps live in ArgoCD (`Ansbile/argocd-apps/<media|monitoring|network>/`). The `k3s_apps` role only owns cluster-wide pieces, rendered from these templates and applied on every run:

| Template                         | Type        | Description                                     |
| :------------------------------- | :---------- | :---------------------------------------------- |
| `node-exporter-daemonset.yml.j2` | DaemonSet   | Runs on all K3s nodes                           |
| `alloy.yml.j2`                   | DaemonSet   | Grafana Alloy log agent on all K3s nodes        |
| `kube-state-metrics.yml.j2`      | Deployment  | K8s object metadata on control plane            |
| `prometheus-rbac.yml.j2`         | RBAC        | ServiceAccount + ClusterRole for kubelet scrape |
| `tempo.yml.j2`                   | Deployment  | Tracing backend for Istio                       |
| `ingress-nginx-values.yml.j2`    | Helm values | ingress-nginx controller config                 |

---

## CI/CD Pipeline

Triggered on push to `development`, `staging`, or `main`, plus a monthly scheduled run.

```text
build-image job
└── Build, scan (Trivy), and push the alert-forwarder image to GHCR

testing job
├── Terraform validate
├── Ansible syntax-check (all playbooks, with vault password)
└── Ansible lint

Deploy job
├── Terraform init + plan (saved to tfplan)
├── Destroy check — fails pipeline if any VM would be destroyed or replaced
└── Ansible playbooks (gateway → monitoring → media → git-k3s)
    └── git-k3s-server bootstraps K3s, Helm infra, ArgoCD, Image Updater
        — ArgoCD then syncs media/monitoring/network from git independently

security job
└── Runs after Deploy, notifies on findings

notify job
└── Posts pipeline result to Discord
```

App-level changes (editing anything under `Ansbile/argocd-apps/`) don't need a CI run to take effect — ArgoCD polls `main` on its own and syncs automatically. CI only needs to run for infra/bootstrap changes.

---

## Observability

### Prometheus Scrape Jobs

| Job                             | Target                             | Notes                                                                              |
| :------------------------------ | :--------------------------------- | :--------------------------------------------------------------------------------- |
| `nodes`                         | node-exporter on all VMs           | `relabel_configs` maps IP → hostname                                               |
| `kubelet-cadvisor`              | kubelet `/metrics/cadvisor`        | HTTPS + bearer token auth                                                          |
| `kube-state-metrics`            | kube-state-metrics pod             | Adds k8s labels to container metrics                                               |
| `loki`                          | Loki on monitoring-server          | Internal metrics                                                                   |
| `qbittorrent`                   | qbittorrent-exporter               | Torrent download/upload/ratio metrics                                              |
| `scraparr`                      | Scraparr on media-server           | Arr app queue/health metrics                                                       |
| `intel-gpu`                     | intel-gpu-exporter on media-server | Arc GPU utilization                                                                |
| `speedtest`                     | speedtest-exporter                 | ISP bandwidth, ping, jitter (1h interval — 10m caused WAN bufferbloat that tripped the blackbox-public alerts) |
| `ingress-nginx`                 | ingress-nginx controller           | Request rate, latency, 5xx rate per service                                        |
| `zfs`                           | zfs-exporter on Proxmox host       | Pool health, IO, capacity                                                          |
| `smartctl_exporter`             | smartctl_exporter on Proxmox host  | Disk S.M.A.R.T. health (reallocated sectors, temperature, wear)                    |
| `argocd-application-controller` | ArgoCD app-controller pod          | Sync/health status per Application (built-in, no separate exporter)                |
| `argocd-server`                 | ArgoCD server pod                  | API request metrics (built-in, no separate exporter)                               |
| `argocd-repo-server`            | ArgoCD repo-server pod             | Git fetch / manifest generation metrics (built-in, no separate exporter)           |
| `tempo`                         | Tempo pod                          | Trace ingestion metrics (built-in, no separate exporter)                           |
| `alloy`                         | Alloy pods (log agent)             | Log pipeline health           |
| `cert-manager`                  | cert-manager controller pod        | Certificate expiry (built-in metrics, no separate exporter)                        |
| `alertmanager-internal`         | Alertmanager pod                   | Alertmanager's own health/notification metrics (built-in, no separate exporter)    |
| `coredns`                       | CoreDNS pod (kube-system)          | DNS query rate/latency/errors (K3s ships the prometheus plugin enabled by default) |

### Loki + Grafana Alloy

- Alloy runs as a DaemonSet on all K3s nodes (`roles/k3s_apps/templates/alloy.yml.j2`, config in `alloy-config.alloy.j2`)
- Labels every line with `host`, `namespace`, `pod`, `container`, `job`
- Reads: K3s container logs (`/var/log/pods`) and system logs (`/var/log/*.log`); read positions persist in `/var/lib/alloy`

### Tracing

- **Istio** ambient mode on `media`, `monitoring`, `network` namespaces (ztunnel mTLS, `media` waypoint), 100% trace sampling to **Tempo** (replaces the earlier Jaeger setup)

### Grafana

- Prometheus and Loki datasources auto-provisioned from `/etc/grafana/provisioning/datasources/`
- Alerts routed via Alertmanager → webhook to notification server
- All Prometheus-evaluated alert rules (nodes, k8s, ingress, istio, blackbox probes, Loki, Tempo, SMART, ZFS, etc.) are repo-managed in `Ansbile/roles/prometheus/templates/prometheus-rules.yml.j2`; log-based (LogQL) alerts are repo-managed in `Ansbile/roles/loki/templates/loki-rules.yml.j2` and evaluated by Loki's ruler. Grafana's UI holds no alert rules — add or change alerts in the repo templates.

---

## Technologies

| Category       | Tools                                                                     |
| :------------- | :------------------------------------------------------------------------ |
| Virtualization | Proxmox VE                                                                |
| IaC            | Terraform (`bpg/proxmox` provider)                                        |
| Configuration  | Ansible                                                                   |
| Orchestration  | K3s (Kubernetes)                                                          |
| GitOps         | ArgoCD, ArgoCD Image Updater                                              |
| Service Mesh   | Istio, Tempo                                                              |
| CI/CD          | GitHub Actions (self-hosted runner on git-k3s-server)                     |
| Metrics        | Prometheus, node-exporter, kubelet-cAdvisor, kube-state-metrics, Scraparr |
| Visualization  | Grafana                                                                   |
| Logging        | Loki, Grafana Alloy                                                            |
| Alerting       | Alertmanager                                                              |
| Reverse Proxy  | Nginx (gateway) + ingress-nginx (K3s)                                     |
| DNS            | AdGuard Home                                                              |
| Media          | Jellyfin, Radarr, Sonarr, Bazarr, Seerr, qBittorrent, Prowlarr        |

---

## Author

Rami Osama Dannah — DevOps Engineer
