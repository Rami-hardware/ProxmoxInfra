# Homelab Infrastructure

A fully automated homelab running on Proxmox, provisioned with Terraform, configured with Ansible, deployed via GitOps with ArgoCD, and monitored end-to-end with Prometheus, Grafana, and Loki.

---

## Architecture

### Physical Host

- **Proxmox VE** on bare metal (`192.168.1.250`)
- Intel Arc GPU passthrough to media VM
- ZFS storage with custom exporter

### Virtual Machines

| VM                | IP            | Cores | RAM  | Role                                      |
| :---------------- | :------------ | :---- | :--- | :---------------------------------------- |
| gateway-server    | 192.168.1.200 | 1     | 2 GB | Reverse proxy, DNS                        |
| media-server      | 192.168.1.201 | 3     | 8 GB | Media stack — K3s worker                  |
| monitoring-server | 192.168.1.203 | 1     | 2 GB | Observability stack — K3s worker          |
| git-k3s-server    | 192.168.1.204 | 4     | 8 GB | GitHub Actions runner + K3s control plane |

---

## GitOps with ArgoCD

App deployment is split across two mechanisms:

- **Ansible** bootstraps the cluster itself — K3s, Helm repos, cert-manager, ingress-nginx, Istio, ArgoCD, ArgoCD Image Updater, and cluster-wide DaemonSets (node-exporter, Promtail, kube-state-metrics).
- **ArgoCD** owns app deployment from here on. Three `Application` resources (`media`, `monitoring`, `network`) auto-sync from `Ansbile/argocd-apps/<name>/` on the `development` branch — editing an app means editing its YAML under `argocd-apps/`, committing, and pushing; ArgoCD picks it up automatically (self-heal + prune enabled, no manual `kubectl apply` needed).

### ArgoCD Image Updater

Tracks the `:latest` (or `:rolling`) tag digest for every app image on a 2-minute poll. When upstream pushes a new image, Image Updater writes a `.argocd-source-<app>.yaml` override into the app's `argocd-apps/` directory and pushes the commit directly to `development` over SSH (deploy key with write access) — ArgoCD then syncs the change automatically. Fully hands-off container updates, no Watchtower needed.

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

### Media (192.168.1.201) — K3s worker, namespace: `media` — ArgoCD-managed

| App          | URL                               | Port | Notes                                         |
| :----------- | :-------------------------------- | :--- | :-------------------------------------------- |
| Jellyfin     | <https://jellyfin.homelab.lan>    | 8096 | Intel Arc GPU transcoding (VAAPI)             |
| Radarr       | <https://radarr.homelab.lan>      | 7878 | Movie automation                              |
| Sonarr       | <https://sonarr.homelab.lan>      | 8989 | TV automation                                 |
| Bazarr       | <https://bazarr.homelab.lan>      | 6767 | Subtitle automation (GPU-accelerated ffmpeg)  |
| Overseerr    | <https://overseerr.homelab.lan>   | 5055 | Media request management                      |
| qBittorrent  | <https://qbittorrent.homelab.lan> | 8080 | Torrent client — BT port 6881 TCP/UDP         |
| Prowlarr     | <https://prowlarr.homelab.lan>    | 9696 | Indexer management                            |
| FlareSolverr | —                                 | 8191 | Cloudflare bypass (stateless, Chromium-based) |
| Scraparr     | —                                 | 7100 | Prometheus metrics exporter for arr apps      |

### Monitoring (192.168.1.203) — K3s worker, namespace: `monitoring` — ArgoCD-managed

| App                  | URL                                | Port  | Notes                              |
| :------------------- | :--------------------------------- | :---- | :--------------------------------- |
| Grafana              | <https://grafana.homelab.lan>      | 3000  | Dashboards                         |
| Prometheus           | <https://prometheus.homelab.lan>   | 9090  | Metrics collection, 30d retention  |
| Loki                 | —                                  | 3100  | Log aggregation                    |
| Alertmanager         | <https://alertmanager.homelab.lan> | 9093  | Alert routing                      |
| Speedtest Exporter   | —                                  | 9798  | ISP bandwidth tracking             |
| qBittorrent Exporter | —                                  | 17871 | qBittorrent metrics for Prometheus |
| Intel GPU Exporter   | —                                  | 8082  | Arc GPU utilization metrics        |

`adguard-exporter` remains Ansible-managed (`k3s_apps_list`) rather than ArgoCD, since it needs real secret handling (AdGuard credentials) that hasn't been wired into git write-back yet.

### Network (192.168.1.200) — K3s worker, namespace: `network` — ArgoCD-managed

| App     | URL                           | Port | Notes                           |
| :------ | :---------------------------- | :--- | :------------------------------ |
| AdGuard | <https://adguard.homelab.lan> | 8081 | DNS + ad blocking (hostNetwork) |

Gateway also runs: **Nginx** (reverse proxy + TLS, routes to K3s NodePorts).

### Git / K3s (192.168.1.204)

- **K3s control plane** — Kubernetes API server
- **GitHub Actions self-hosted runner** — executes CI/CD pipeline
- **ArgoCD + ArgoCD Image Updater** — GitOps sync + auto image updates
- **cert-manager** — TLS via internal CA (`homelab-ca-issuer`)
- **ingress-nginx** — Kubernetes ingress controller (Helm-managed, LoadBalancer at `192.168.1.210`)
- **Istio** (`istio-base` + `istiod`) — service mesh, sidecar injection on `media`, `monitoring`, `network` namespaces, traces to Tempo
- **kube-state-metrics** — Kubernetes object metadata exported to Prometheus

### Cluster-wide DaemonSets

| Component        | Nodes                                      | Description                            |
| :--------------- | :----------------------------------------- | :------------------------------------- |
| node-exporter    | media, monitoring, git-k3s-server, gateway | Host-level CPU / memory / disk metrics |
| Promtail         | media, monitoring, git-k3s-server, gateway | Log shipping to Loki                   |
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

- All modules use FQCN (`ansible.builtin.*`, `community.docker.*`)
- All configs rendered from Jinja2 templates — no inline hardcoded content
- IPs reference `hostvars[host]['ansible_host']` from inventory — single source of truth
- Secrets stored in Ansible Vault
- Role variable naming follows `<role_name>_` prefix convention
- Owns cluster bootstrap (K3s, Helm-based infra, DaemonSets) — no longer owns app rollout for `media`/`monitoring`/`network` namespaces, see [GitOps with ArgoCD](#gitops-with-argocd)

### K3s App Pattern (Ansible-managed apps only)

Apps still in `k3s_apps_list` (currently just `adguard-exporter`) render through one generic template (`app.yml.j2`) — Namespace + PV + PVC + Deployment + NodePort Service — from an entry in `group_vars/git-k3s-server-vm.yml`:

```yaml
k3s_apps_list:
  - name: myapp
    namespace: media
    image: myrepo/myapp:latest
    port: 8080
    node_port: 8080
    target_node: media-server
    config_path: /opt/myapp
    config_mount: /config
    replicas: 1
    env:
      - { name: TZ, value: "Asia/Riyadh" }
    memory_request: "128Mi"
    memory_limit: "512Mi"
    cpu_request: "100m"
    cpu_limit: "500m"
```

New apps that don't need secrets should go into ArgoCD instead — add a manifest under `Ansbile/argocd-apps/<media|monitoring|network>/`, list it in that directory's `kustomization.yaml`, and it's live on next sync.

**Supported flags:**

| Flag              | Description                                                      |
| :---------------- | :--------------------------------------------------------------- |
| `skip_pv`         | Skip PV/PVC creation for stateless apps                          |
| `gpu`             | Mount `/dev/dri` + privileged for Intel Arc GPU access           |
| `privileged`      | Run container as privileged (no GPU mount)                       |
| `host_pid`        | Enable `hostPID: true`                                           |
| `host_network`    | Enable `hostNetwork: true`                                       |
| `external_ip`     | Bind Service to a specific host IP via `externalIPs`             |
| `service_account` | Attach a named ServiceAccount to the pod                         |
| `dns_policy`      | Override DNS policy (e.g. `None` for custom nameservers)         |
| `dns_nameservers` | Custom nameservers when `dns_policy: None`                       |
| `args`            | Container CLI arguments                                          |
| `extra_volumes`   | Additional hostPath volume mounts                                |
| `extra_ports`     | Additional Service + hostPort entries (e.g. qBittorrent BT port) |

**Special manifests deployed outside the generic template:**

| Template                         | Type        | Description                                     |
| :------------------------------- | :---------- | :---------------------------------------------- |
| `node-exporter-daemonset.yml.j2` | DaemonSet   | Runs on all K3s nodes                           |
| `promtail-daemonset.yml.j2`      | DaemonSet   | Runs on all K3s nodes                           |
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
└── Ansible playbooks (monitoring-server → git-k3s-server)
    └── git-k3s-server bootstraps K3s, Helm infra, ArgoCD, Image Updater
        — ArgoCD then syncs media/monitoring/network from git independently

security job
└── Runs after Deploy, notifies on findings

notify job
└── Posts pipeline result to Discord
```

App-level changes (editing anything under `Ansbile/argocd-apps/`) don't need a CI run to take effect — ArgoCD polls `development` on its own and syncs automatically. CI only needs to run for infra/bootstrap changes.

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
| `speedtest`                     | speedtest-exporter                 | ISP bandwidth, ping, jitter (10m interval)                                         |
| `ingress-nginx`                 | ingress-nginx controller           | Request rate, latency, 5xx rate per service                                        |
| `zfs`                           | zfs-exporter on Proxmox host       | Pool health, IO, capacity                                                          |
| `smartctl_exporter`             | smartctl_exporter on Proxmox host  | Disk S.M.A.R.T. health (reallocated sectors, temperature, wear)                    |
| `argocd-application-controller` | ArgoCD app-controller pod          | Sync/health status per Application (built-in, no separate exporter)                |
| `argocd-server`                 | ArgoCD server pod                  | API request metrics (built-in, no separate exporter)                               |
| `argocd-repo-server`            | ArgoCD repo-server pod             | Git fetch / manifest generation metrics (built-in, no separate exporter)           |
| `tempo`                         | Tempo pod                          | Trace ingestion metrics (built-in, no separate exporter)                           |
| `promtail`                      | Promtail pods                      | Log pipeline health                                                                |
| `cert-manager`                  | cert-manager controller pod        | Certificate expiry (built-in metrics, no separate exporter)                        |
| `alertmanager-internal`         | Alertmanager pod                   | Alertmanager's own health/notification metrics (built-in, no separate exporter)    |
| `coredns`                       | CoreDNS pod (kube-system)          | DNS query rate/latency/errors (K3s ships the prometheus plugin enabled by default) |

### Loki + Promtail

- Promtail runs as DaemonSet on all K3s nodes
- `${NODE_NAME}` injected via downward API — each pod labels logs with its node name
- Scrapes: K3s container logs (`/var/log/pods`), Docker container logs, system logs (`/var/log`)

### Tracing

- **Istio** sidecar injection on `media`, `monitoring`, `network` namespaces, 100% trace sampling to **Tempo** (replaces the earlier Jaeger setup)

### Grafana

- Prometheus and Loki datasources auto-provisioned from `/etc/grafana/provisioning/datasources/`
- Alerts routed via Alertmanager → webhook to notification server

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
| Logging        | Loki, Promtail                                                            |
| Alerting       | Alertmanager                                                              |
| Reverse Proxy  | Nginx (gateway) + ingress-nginx (K3s)                                     |
| DNS            | AdGuard Home                                                              |
| Media          | Jellyfin, Radarr, Sonarr, Bazarr, Overseerr, qBittorrent, Prowlarr        |

---

## Author

Rami Osama Dannah — DevOps Engineer
