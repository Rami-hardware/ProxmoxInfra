# Alert runbooks

Every alert annotation links here. One runbook per alert family.

| Runbook | Alerts |
|---|---|
| [nodes.md](nodes.md) | node/VM health: disk, memory, load, OOM, clock, network |
| [k3s-datastore.md](k3s-datastore.md) | nightly k3s sqlite snapshot; restoring the control plane from it |
| [sites.md](sites.md) | HTTP probes, SLO burn (local/public), blackbox, speedtest |
| [dns.md](dns.md) | AdGuard Home + CoreDNS chain |
| [k8s-workloads.md](k8s-workloads.md) | deployments, pods, PVCs, jobs, nodes, kubelet |
| [ingress.md](ingress.md) | ingress-nginx controller and routes |
| [istio-tempo.md](istio-tempo.md) | Istio mesh + Tempo tracing |
| [loki-logs.md](loki-logs.md) | Loki pipeline, Alloy (log agent), log-based alerts |
| [argocd-alertmanager.md](argocd-alertmanager.md) | GitOps + notification path |
| [exporters.md](exporters.md) | SMART, ZFS, scraparr, qBittorrent, Intel GPU, cert-manager |
| [slo.md](slo.md) | SLO burn alerts and the error budget |
| [ci-runners.md](ci-runners.md) | GitHub Actions runners: offline, lost jobs (Discord, not Prometheus) |

Conventions: diagnosis commands first, then fixes, then escalation. If a fix
isn't written here yet, add it after the incident — the runbook is the memory.
