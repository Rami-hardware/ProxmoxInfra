# Homelab Infrastructure

A fully automated homelab running on Proxmox, provisioned with Terraform, configured with Ansible, and monitored end-to-end with Prometheus, Grafana, and Loki.

---

## Architecture

### Physical Host

- **Proxmox VE** on bare metal (`192.168.1.250`)
- Intel Arc GPU passthrough to media VM
- ZFS storage with custom exporter

### Virtual Machines

| VM                | IP            | Cores | RAM  | Role                                      |
| :---------------- | :------------ | :---- | :--- | :---------------------------------------- |
| gateway-server    | 192.168.1.200 | 1     | 2 GB | Reverse proxy, firewall, DNS              |
| media-server      | 192.168.1.201 | 3     | 8 GB | Media stack — K3s worker                  |
| monitoring-server | 192.168.1.203 | 1     | 2 GB | Observability stack — K3s worker          |
| git-k3s-server    | 192.168.1.204 | 4     | 8 GB | GitHub Actions runner + K3s control plane |
| dev-server        | 192.168.1.205 | 2     | 1 GB | Development                               |

---

## Services

### Media (192.168.1.201) — K3s worker, namespace: `media`

| App          | URL                                    | Port  | Notes                                         |
| :----------- | :------------------------------------- | :---- | :-------------------------------------------- |
| Jellyfin     | <https://jellyfin.homelab.lan>         | 8096  | Intel Arc GPU transcoding (VAAPI)             |
| Radarr       | <https://radarr.homelab.lan>           | 7878  | Movie automation                              |
| Sonarr       | <https://sonarr.homelab.lan>           | 8989  | TV automation                                 |
| Bazarr       | <https://bazarr.homelab.lan>           | 6767  | Subtitle automation (GPU-accelerated ffmpeg)  |
| Overseerr    | <https://overseerr.homelab.lan>        | 5055  | Media request management                      |
| qBittorrent  | <https://qbittorrent.homelab.lan>      | 8080  | Torrent client — BT port 6881 TCP/UDP         |
| Prowlarr     | <https://prowlarr.homelab.lan>         | 9696  | Indexer management                            |
| FlareSolverr | —                                      | 8191  | Cloudflare bypass (stateless, Chromium-based) |
| Scraparr     | —                                      | 7100  | Prometheus metrics exporter for arr apps      |

### Monitoring (192.168.1.203) — K3s worker, namespace: `monitoring`

| App                  | URL                                    | Port  | Notes                              |
| :------------------- | :------------------------------------- | :---- | :--------------------------------- |
| Grafana              | <https://grafana.homelab.lan>          | 3000  | Dashboards                         |
| Prometheus           | <https://prometheus.homelab.lan>       | 9090  | Metrics collection, 30d retention  |
| Loki                 | —                                      | 3100  | Log aggregation                    |
| Alertmanager         | <https://alertmanager.homelab.lan>     | 9093  | Alert routing                      |
| Speedtest Exporter   | —                                      | 9798  | ISP bandwidth tracking             |
| qBittorrent Exporter | —                                      | 17871 | qBittorrent metrics for Prometheus |
| Intel GPU Exporter   | —                                      | 8082  | Arc GPU utilization metrics        |

### Network (192.168.1.200) — K3s worker, namespace: `network`

| App      | URL                              | Port | Notes                           |
| :------- | :------------------------------- | :--- | :------------------------------ |
| AdGuard  | <https://adguard.homelab.lan>    | 8081 | DNS + ad blocking (hostNetwork) |
| Authelia | <https://auth.homelab.lan>       | 9091 | SSO / 2FA                       |

Gateway also runs: **Nginx** (reverse proxy + TLS), **CrowdSec** (IDS + nginx bouncer), **UFW** (host firewall).

### Git / K3s (192.168.1.204)

- **K3s control plane** — Kubernetes API server
- **GitHub Actions self-hosted runner** — executes CI/CD pipeline
- **kube-state-metrics** — Kubernetes object metadata exported to Prometheus

### Cluster-wide DaemonSets

| Component        | Nodes                             | Description                            |
| :--------------- | :-------------------------------- | :------------------------------------- |
| node-exporter    | media, monitoring, git-k3s-server | Host-level CPU / memory / disk metrics |
| Promtail         | media, monitoring, git-k3s-server | Log shipping to Loki                   |
| kubelet-cAdvisor | media, monitoring, git-k3s-server | Container metrics via kubelet API      |

---

## Infrastructure as Code

### Terraform

- Provider: `bpg/proxmox`
- All VMs defined as a `map(object)` in `terraform.tfvars` — add/change a VM by editing one block
- Module at `modules/proxmox_vm/` handles all VM resources
- `lifecycle.ignore_changes` covers `disk`, `initialization`, `clone`, `hostpci`, `cpu`
- State tracked per VMID — map keys must never be renamed (would destroy the VM)
- `parallelism=1` required on self-hosted runner to avoid Proxmox API race conditions

### Ansible

- All modules use FQCN (`ansible.builtin.*`, `community.docker.*`)
- All configs rendered from Jinja2 templates — no inline hardcoded content
- IPs reference `hostvars[host]['ansible_host']` from inventory — single source of truth
- Secrets stored in Ansible Vault (`group_vars/vault.yml`)
- Role variable naming follows `<role_name>_` prefix convention

### K3s App Pattern

One generic template (`app.yml.j2`) renders Namespace + PV + PVC + Deployment + NodePort Service for every app. Adding a new app only requires a new entry in `group_vars/git-k3s-server-vm.yml`:

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

**Supported flags:**

| Flag              | Description                                                      |
| :---------------- | :--------------------------------------------------------------- |
| `skip_pv`         | Skip PV/PVC creation for stateless apps                          |
| `gpu`             | Mount `/dev/dri` + privileged for Intel Arc GPU access           |
| `privileged`      | Run container as privileged (no GPU mount)                       |
| `host_pid`        | Enable `hostPID: true`                                           |
| `host_network`    | Enable `hostNetwork: true` (used by AdGuard for DNS port 53)     |
| `external_ip`     | Bind Service to a specific host IP via `externalIPs`             |
| `service_account` | Attach a named ServiceAccount to the pod                         |
| `dns_policy`      | Override DNS policy (e.g. `None` for custom nameservers)         |
| `dns_nameservers` | Custom nameservers when `dns_policy: None`                       |
| `args`            | Container CLI arguments                                          |
| `extra_volumes`   | Additional hostPath volume mounts                                |
| `extra_ports`     | Additional Service + hostPort entries (e.g. qBittorrent BT port) |

**Special manifests deployed outside the generic template:**

| Template                         | Type       | Description                                     |
| :------------------------------- | :--------- | :---------------------------------------------- |
| `node-exporter-daemonset.yml.j2` | DaemonSet  | Runs on all K3s nodes                           |
| `promtail-daemonset.yml.j2`      | DaemonSet  | Runs on all K3s nodes                           |
| `kube-state-metrics.yml.j2`      | Deployment | K8s object metadata on control plane            |
| `prometheus-rbac.yml.j2`         | RBAC       | ServiceAccount + ClusterRole for kubelet scrape |
| `ingress-nginx.yml.j2`           | Deployment | Ingress controller (gzip, 1h timeout)           |

---

## CI/CD Pipeline

Triggered on push to `development`, `staging`, or `main`.

```text
Testing job
├── Terraform validate
├── Ansible syntax-check (all playbooks, with vault password)
└── Ansible lint

Deploy job
├── Terraform init
├── Import existing VMs into state
├── Terraform plan (saved to tfplan)
├── Destroy check — fails pipeline if any VM would be destroyed or replaced
├── Terraform apply -parallelism=1 (targeted per VM)
└── Ansible playbooks (gateway → monitoring → media → git-k3s-server)
```

The destroy guard parses the saved plan and blocks apply if `will be destroyed` or `must be replaced` is detected.

---

## Observability

### Prometheus Scrape Jobs

| Job                  | Target                             | Notes                                       |
| :------------------- | :--------------------------------- | :------------------------------------------ |
| `nodes`              | node-exporter on all VMs           | `relabel_configs` maps IP → hostname        |
| `kubelet-cadvisor`   | kubelet `/metrics/cadvisor`        | HTTPS + bearer token auth                   |
| `kube-state-metrics` | kube-state-metrics pod             | Adds k8s labels to container metrics        |
| `loki`               | Loki on monitoring-server          | Internal metrics                            |
| `qbittorrent`        | qbittorrent-exporter               | Torrent download/upload/ratio metrics       |
| `scraparr`           | Scraparr on media-server           | Arr app queue/health metrics                |
| `intel-gpu`          | intel-gpu-exporter on media-server | Arc GPU utilization                         |
| `speedtest`          | speedtest-exporter                 | ISP bandwidth, ping, jitter (10m interval)  |
| `ingress-nginx`      | ingress-nginx controller           | Request rate, latency, 5xx rate per service |
| `zfs`                | zfs-exporter on Proxmox host       | Pool health, IO, capacity                   |
| `promtail`           | Promtail pods                      | Log pipeline health                         |

### Loki + Promtail

- Promtail runs as DaemonSet on all K3s nodes
- `${NODE_NAME}` injected via downward API — each pod labels logs with its node name
- Scrapes: K3s container logs (`/var/log/pods`), Docker container logs, system logs (`/var/log`)

### Grafana

- Prometheus and Loki datasources auto-provisioned from `/etc/grafana/provisioning/datasources/`
- Alerts routed via Alertmanager → webhook to notification server at `192.168.1.203:3002`

---

## Technologies

| Category       | Tools                                                                      |
| :------------- | :------------------------------------------------------------------------- |
| Virtualization | Proxmox VE                                                                 |
| IaC            | Terraform (`bpg/proxmox` provider)                                         |
| Configuration  | Ansible                                                                    |
| Orchestration  | K3s (Kubernetes)                                                           |
| CI/CD          | GitHub Actions (self-hosted runner on git-k3s-server)                      |
| Metrics        | Prometheus, node-exporter, kubelet-cAdvisor, kube-state-metrics, Scraparr  |
| Visualization  | Grafana                                                                    |
| Logging        | Loki, Promtail                                                             |
| Alerting       | Alertmanager                                                               |
| Reverse Proxy  | Nginx (gateway) + ingress-nginx (K3s)                                      |
| DNS            | AdGuard Home                                                               |
| Media          | Jellyfin, Radarr, Sonarr, Bazarr, Overseerr, qBittorrent, Prowlarr         |

---

## Author

Rami Osama Dannah — DevOps Engineer
