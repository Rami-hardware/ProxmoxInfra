# Homelab Infrastructure

A fully automated homelab running on Proxmox, provisioned with Terraform, configured with Ansible, and monitored end-to-end with Prometheus, Grafana, and Loki — all running as K3s workloads.

---

## Architecture

### Physical Host

- **Proxmox VE** on bare metal (`192.168.1.250`)
- Intel Arc GPU passthrough to media VM
- ZFS storage with custom exporter

### Virtual Machines

| VM                | IP            | VMID | Cores | RAM   | Role                                      |
| :---------------- | :------------ | :--- | :---- | :---- | :---------------------------------------- |
| gateway-server    | 192.168.1.200 | 505  | 1     | 3 GB  | Reverse proxy, firewall, DNS, K3s worker  |
| media-server      | 192.168.1.201 | 911  | 4     | 10 GB | Media stack, K3s worker                   |
| security-server   | 192.168.1.202 | 619  | 2     | 3 GB  | Security tooling, K3s worker              |
| monitoring-server | 192.168.1.203 | 511  | 1     | 5 GB  | Observability stack, K3s worker           |
| git-k3s-server    | 192.168.1.204 | 115  | 3     | 7 GB  | GitHub Actions runner, K3s control plane  |

---

## Services

### Gateway (192.168.1.200) — K3s worker

- **Nginx** — reverse proxy for all internal services
- **AdGuard Home** — local DNS + ad blocking (K3s, `host_network` mode)

### Media (192.168.1.201) — K3s worker

| App                  | Port  | Description                                    |
| :------------------- | :---- | :--------------------------------------------- |
| Jellyfin             | 8096  | Media server with Intel Arc GPU transcoding    |
| Radarr               | 7878  | Movie automation                               |
| Sonarr               | 8989  | TV automation                                  |
| Bazarr               | 6767  | Subtitle automation                            |
| Overseerr            | 5055  | Media request management                       |
| qBittorrent          | 8080  | Torrent client                                 |
| Prowlarr             | 9696  | Indexer management                             |
| FlareSolverr         | 8191  | Cloudflare bypass (stateless)                  |
| Subsyncarr           | —     | Subtitle sync with VAAPI hardware acceleration |
| Scraparr             | 7100  | Metrics exporter for arr apps                  |
| intel-gpu-exporter   | 8082  | Intel Arc GPU metrics                          |
| qbittorrent-exporter | 17871 | qBittorrent metrics                            |

### Security (192.168.1.202) — K3s worker

- DNS configuration
- K3s agent node

### Monitoring (192.168.1.203) — K3s worker

| App                | Port | Description                           |
| :----------------- | :--- | :------------------------------------ |
| Prometheus         | 9090 | Metrics collection (30d retention)    |
| Grafana            | 3000 | Dashboards                            |
| Loki               | 3100 | Log aggregation                       |
| Alertmanager       | 9093 | Alert routing                         |
| Speedtest Exporter | 9798 | ISP bandwidth tracking (10m interval) |

### Git / K3s (192.168.1.204) — K3s control plane

- **GitHub Actions self-hosted runner** — executes CI/CD pipeline
- **K3s control plane** — Kubernetes API server
- **kube-state-metrics** — Kubernetes object metadata for dashboards

### Observability (cluster-wide DaemonSets)

| Component        | Nodes                                          | Description                   |
| :--------------- | :--------------------------------------------- | :---------------------------- |
| node-exporter    | media, monitoring, security, git-k3s-server    | Host-level metrics            |
| Promtail         | media, monitoring, gateway, git-k3s-server     | Log shipping to Loki          |
| kubelet-cadvisor | media, monitoring, security, git-k3s-server    | Container metrics via kubelet |

---

## Infrastructure as Code

### Terraform

- Provider: `bpg/proxmox` v0.70.1
- All VMs defined as a `map(object)` in `terraform.tfvars` — add/change a VM by editing one block
- Module at `modules/proxmox_vm/` handles all VM resources
- `lifecycle.ignore_changes` covers `disk`, `initialization`, `clone`, `hostpci`, `cpu`, all timeout attributes, `agent`, `operating_system`, `migrate`, `on_boot`, `reboot`, `stop_on_destroy`
- State tracked per VMID — map keys must never be renamed (would destroy the VM)
- `parallelism=1` required on self-hosted runner to avoid Proxmox API race conditions
- `git-k3s-server` is intentionally excluded from CI apply targets (managed manually)
- Sensitive variables (`pm_api_url`, `pm_api_token`, `ssh_public_key`) passed via `TF_VAR_*` environment variables

### Ansible

- All modules use FQCN (`ansible.builtin.*`, `community.docker.*`)
- All configs rendered from Jinja2 templates — no inline hardcoded content
- IPs reference `hostvars[host]['ansible_host']` from inventory — single source of truth
- Secrets stored in Ansible Vault (`group_vars/vault.yml`)
- Role variable naming follows `<role_name>_` prefix convention

### K3s App Pattern

One generic template (`app.yml.j2`) renders Namespace + PV + PVC + Deployment + NodePort Service. Adding a new app requires only a new entry in `group_vars/git-k3s-server-vm.yml`:

```yaml
k3s_apps_list:
  - name: myapp
    namespace: media
    image: myrepo/myapp:latest
    port: 8080
    node_port: 8080
    target_node: media-server
    config_path: /opt/myapp         # omit + set skip_pv: true for stateless apps
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

| Flag              | Description                                          |
| :---------------- | :--------------------------------------------------- |
| `skip_pv`         | Skip PV/PVC creation for stateless apps              |
| `gpu`             | Mount `/dev/dri` + privileged for Intel GPU access   |
| `privileged`      | Run container as privileged (no GPU mount)           |
| `host_pid`        | Enable `hostPID: true`                               |
| `host_network`    | Enable `hostNetwork: true` with `dnsPolicy: Default` |
| `service_account` | Attach a named ServiceAccount to the pod             |
| `dns_policy`      | Override DNS policy (e.g. `None`)                    |
| `dns_nameservers` | Custom nameservers when `dns_policy: None`           |
| `args`            | Container CLI arguments                              |
| `extra_volumes`   | Additional hostPath volume mounts                    |
| `external_ip`     | Expose service on a specific host IP                 |

**Special apps deployed as static manifests (not via generic template):**

| Manifest                 | Type       | Description                           |
| :----------------------- | :--------- | :------------------------------------ |
| `node-exporter.yml`      | DaemonSet  | Runs on all K3s nodes                 |
| `promtail.yml`           | DaemonSet  | Runs on all K3s nodes                 |
| `kube-state-metrics.yml` | Deployment | K8s metadata metrics on control plane |
| `prometheus-rbac.yml`    | RBAC       | Allows Prometheus to scrape kubelet   |

---

## CI/CD Pipeline

Triggered on push to `development`, `staging`, or `main`.

```text
Testing job
├── Install system dependencies (idempotent — skips if already present)
├── Configure Terraform filesystem provider mirror (offline-safe)
├── Seed provider mirror (bpg/proxmox v0.70.1)
├── Terraform init (no backend)
├── Terraform fmt check
├── Terraform validate
├── Install ansible-lint in virtualenv (idempotent)
├── Install Ansible collections
├── Ansible syntax-check (security-server.yml)
├── Ansible lint
└── Ansible dry run --check --diff (security-server.yml)

Deploy job
├── Configure Terraform filesystem provider mirror
├── Seed provider mirror
├── Terraform init
├── Import existing VMs into state (gateway, media, monitoring, security, github)
├── Remove stale state entries (monitor, game, dev, securtiy typo)
├── Terraform plan -detailed-exitcode (saved to tfplan)
├── Destroy check — fails pipeline if any VM would be destroyed or replaced
├── Terraform apply -parallelism=1 (gateway, media, monitoring, security only)
└── Ansible playbook: security-server.yml
```

The destroy guard parses the saved plan and blocks apply if `will be destroyed` or `must be replaced` is detected.

The provider mirror is seeded from GitHub Releases on first run and cached on the runner — `terraform init` never contacts `registry.terraform.io`.

---

## Observability

### Prometheus Scrape Design

- `nodes` job groups all node-exporters with `relabel_configs` — instance label shows hostname, not IP
- `kubelet-cadvisor` job scrapes `/metrics/cadvisor` from each kubelet over HTTPS with bearer token auth
- `kube-state-metrics` provides Kubernetes object labels (namespace, pod, container) to enrich container metrics
- `intel-gpu-exporter` exposes Intel Arc GPU utilization and memory from the media node
- `qbittorrent-exporter` exposes download/upload/peer metrics from qBittorrent
- Scrape targets reference `hostvars` IPs — no duplication with inventory

### Loki + Promtail

- Promtail runs as a DaemonSet on all K3s nodes
- `${NODE_NAME}` injected via downward API — each pod labels logs with its actual node name
- Scrapes: K3s container logs, Docker container logs, system logs

### Grafana

- Prometheus and Loki datasources auto-provisioned at `/etc/grafana/provisioning/datasources/`

---

## Technologies

| Category | Tools |
| :--- | :--- |
| Virtualization | Proxmox VE |
| IaC | Terraform (bpg/proxmox provider v0.70.1) |
| Configuration | Ansible |
| Containers | Docker, Docker Compose |
| Orchestration | K3s (Kubernetes) |
| CI/CD | GitHub Actions (self-hosted runner) |
| Metrics | Prometheus, node-exporter, kubelet-cadvisor, kube-state-metrics, intel-gpu-exporter, qbittorrent-exporter, scraparr |
| Visualization | Grafana |
| Logging | Loki, Promtail |
| Alerting | Alertmanager |
| Reverse Proxy | Nginx |
| Security | CrowdSec, Authelia, UFW, Ansible Vault |
| DNS | AdGuard Home |
| Media | Jellyfin, Radarr, Sonarr, Bazarr, Overseerr, qBittorrent, Subsyncarr |

---

## Author

Rami Osama Dannah — DevOps Engineer
