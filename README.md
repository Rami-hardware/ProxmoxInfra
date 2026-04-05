# Homelab Infrastructure

A fully automated homelab running on Proxmox, provisioned with Terraform, configured with Ansible, and monitored end-to-end with Prometheus, Grafana, and Loki.

---

## Architecture

### Physical Host

- **Proxmox VE** on bare metal (`192.168.1.250`)
- Intel Arc GPU passthrough to media VM
- ZFS storage with custom exporter

### Virtual Machines

| VM                | Key        | IP            | Cores | RAM  | Role                                      |
| :---------------- | :--------- | :------------ | :---- | :--- | :---------------------------------------- |
| gateway-server    | gateway    | 192.168.1.200 | 1     | 2 GB | Reverse proxy, firewall, DNS              |
| media-server      | media      | 192.168.1.201 | 3     | 8 GB | Media stack + K3s agent                   |
| monitoring-server | monitoring | 192.168.1.203 | 1     | 2 GB | Observability stack                       |
| git-k3s-server    | github     | 192.168.1.204 | 4     | 8 GB | GitHub Actions runner + K3s control plane |
| dev-server        | dev        | 192.168.1.205 | 2     | 1 GB | Development                               |
| game-server       | game       | 192.168.1.202 | 4     | 8 GB | Game server                               |

---

## Services

### Gateway (192.168.1.200)

- **Nginx** — reverse proxy for all internal services
- **CrowdSec** — intrusion detection + nginx bouncer
- **AdGuard Home** — local DNS + ad blocking
- **Authelia** — SSO / 2FA authentication layer
- **UFW** — host firewall

### Media (192.168.1.201)

- **Jellyfin** — media server with Intel Arc GPU transcoding
- **Radarr / Sonarr / Bazarr** — movie, TV, subtitle automation
- **qBittorrent** — torrent client
- **Prowlarr / FlareSolverr** — indexer management
- **Overseerr** — media request management (deployed via K3s)
- **Samba** — network file share for `/mnt/media`
- **Subsyncarr** — subtitle sync with hardware acceleration

### Monitoring (192.168.1.203)

- **Prometheus** — metrics collection with relabel_configs for clean instance labels
- **Grafana** — dashboards with auto-provisioned Prometheus + Loki datasources
- **Loki** — log aggregation
- **Alertmanager** — alert routing to webhook
- **Promtail** — log shipping from all hosts
- **node-exporter** — host metrics
- **speedtest-exporter** — ISP bandwidth tracking (1h interval)

### Git / K3s (192.168.1.204)

- **GitHub Actions self-hosted runner** — executes CI/CD pipeline
- **K3s control plane** — Kubernetes API server
- **K3s apps** — single Ansible role deploys any app via one generic manifest template

---

## Infrastructure as Code

### Terraform

- Provider: `bpg/proxmox`
- All VMs defined as a `map(object)` in `terraform.tfvars` — add/change a VM by editing one block
- Module at `modules/proxmox_vm/` handles all VM resources
- `lifecycle.ignore_changes` covers `disk`, `initialization`, `clone`, `hostpci`, `cpu`
- State tracked per VMID — map keys must never be renamed (would destroy the VM)

### Ansible

- All modules use FQCN (`ansible.builtin.*`, `community.docker.*`)
- All configs rendered from Jinja2 templates — no inline hardcoded content
- IPs reference `hostvars[host]['ansible_host']` from inventory — single source of truth
- Secrets stored in Ansible Vault (`group_vars/vault.yml`)
- Role variable naming follows `<role_name>_` prefix convention

### K3s App Pattern

Adding a new K3s app requires only editing `group_vars/github-vm.yml`:

```yaml
k3s_apps_list:
  - name: overseerr
    namespace: overseerr
    image: sctx/overseerr:latest
    port: 5055
    node_port: 30055
    target_node: media-server
    config_path: /opt/k3s/overseerr/config
    config_mount: /app/config
    env:
      - { name: TZ, value: "Asia/Riyadh" }
    memory_request: "128Mi"
    memory_limit: "512Mi"
    cpu_request: "100m"
    cpu_limit: "500m"
```

One generic template (`app.yml.j2`) renders Namespace + PV + PVC + Deployment + NodePort Service for every app.

---

## CI/CD Pipeline

Triggered on push to `development`, `staging`, or `main`.

```
Testing job
├── Terraform validate
├── Ansible syntax-check (all playbooks)
└── Ansible lint

Deploy job
├── Terraform init
├── Import existing VMs into state
├── Terraform plan (saved to tfplan)
├── Destroy check — fails pipeline if any VM would be destroyed
├── Terraform apply -parallelism=1 (targeted per VM)
└── Ansible playbooks (monitoring → media → github)
```

The destroy guard parses the saved plan and blocks apply if `will be destroyed` or `must be replaced` is detected.

---

## Observability

### Prometheus Scrape Design

- All node exporters grouped into a single `nodes` job with `relabel_configs` — instance label shows hostname, not IP
- Single-target jobs use `relabel_configs: target_label: instance` — reliable override vs `static_configs.labels`
- Scrape targets reference `hostvars` for IPs — no duplication with inventory

### Loki

- `reject_old_samples: true` with `reject_old_samples_max_age: 168h` — prevents log drop on Promtail restart
- BoltDB shipper with filesystem chunks storage

### Grafana

- Prometheus and Loki datasources auto-provisioned at `/etc/grafana/provisioning/datasources/` — no manual UI setup required

### Promtail

- Uses `HOST_HOSTNAME` env var (not `HOSTNAME` — Docker overrides that to the container ID)
- Scrapes: system logs, Docker container logs, Samba logs

---

## Technologies

| Category       | Tools                                              |
| -------------- | -------------------------------------------------- |
| Virtualization | Proxmox VE                                         |
| IaC            | Terraform (bpg/proxmox provider)                   |
| Configuration  | Ansible                                            |
| Containers     | Docker, Docker Compose                             |
| Orchestration  | K3s (Kubernetes)                                   |
| CI/CD          | GitHub Actions (self-hosted runner)                |
| Metrics        | Prometheus, node-exporter, various exporters       |
| Visualization  | Grafana                                            |
| Logging        | Loki, Promtail                                     |
| Alerting       | Alertmanager                                       |
| Reverse Proxy  | Nginx                                              |
| Security       | CrowdSec, Authelia, UFW, Ansible Vault             |
| DNS            | AdGuard Home                                       |
| Media          | Jellyfin, Radarr, Sonarr, Bazarr, Overseerr        |

---

## Author

Rami Osama Dannah — DevOps Engineer
