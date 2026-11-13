# Hardware & app exporters — SMART / ZFS / scraparr / qBittorrent / GPU

Covers: DiskSmartUnhealthy, DiskSectorProblems, DiskTemperatureHigh, NVMeHealthWarning,
NVMeWearHigh, SmartDataStale, Zfs*, Scraparr*, Qbit*, IntelGpu*, CertManagerCertNotReady,
BlackboxExporterDown

## Quick pointers
- SMART (host disks): `smartctl -a /dev/sdX` on the Proxmox host; reallocated
  or pending sectors > 0 = plan replacement, run a long self-test.
  Data: the smartctl textfile collector on host-node (`smartmon_*`, every few
  minutes) and node-exporter's NVMe collector (`nvme_*`). SmartDataStale = that
  collector stopped, so the disk alerts are blind until it runs again.
- ZFS: `zpool status tank`, `zpool list` on the host. DEGRADED = act now.
- qBittorrent: Web UI at 192.168.10.201:8080; stalled downloads usually mean
  dead torrents or tracker/network issues (check port forwarding).
- scraparr: per-arr health — Sonarr/Radarr queues are app-side
  (Activity > Queue); Prowlarr indexer failures = indexers rate-limiting you.
- ScraparrBazarrProviderDegraded: fires only after a provider reports a bad
  status (other than Good/DownloadLimitExceeded) continuously for 20m. Check
  `bazarr_provider_status` in Prometheus to see which provider/status; if it's
  already Good again, the provider self-healed. Quota throttles
  (DownloadLimitExceeded) are excluded by design — Bazarr auto-retries.
- Intel GPU: sustained >90% engine busy or power draw = check active Jellyfin
  transcodes; the iGPU idles at ~100% RC6 residency.
- cert-manager: `kubectl describe certificate -A` and CertificateRequest events.
- Proxmox (pve-exporter): `systemctl status pve_exporter` on host-node, and
  `curl -s 'localhost:9221/pve?target=localhost&module=default' | head`.
  ProxmoxExporterDown usually = the service is stopped or the PVE API token
  expired/was deleted. ProxmoxStorageUsageHigh = a storage (`pvesm status`)
  is >90% full; clear old backups/ISOs/unused disks or expand it.

## Exporter inventory on host-node (.250)

All of these are managed by Ansible (`roles/proxmox_exporters`, playbook
`host-node.yml`) — do not hand-install or hand-edit the units on the host.

| Port | Exporter | Install | Feeds |
| :--- | :--- | :--- | :--- |
| 9100 | prometheus-node-exporter (apt) | `apt` + smartmon/nvme/apt textfile **timers** | `node_*`, `smartmon_*`, `nvme_*` (SMART source) |
| 9134 | zfs_exporter (pinned binary) | GitHub release | `zfs_*` |
| 9221 | prometheus-pve-exporter (venv) | PyPI in `/opt/pve-exporter` | `pve_*` (Proxmox API) |

The smartmon/nvme data comes from node-exporter's oneshot textfile **timers**
(`prometheus-node-exporter-smartmon.timer` etc.), which write `.prom` files that
node-exporter reads — the `.service` units showing `dead` between runs is
normal. There is no standalone smartctl exporter (the old snap on :9633 emitted
nothing and was removed).

### One-time setup for pve-exporter

pve-exporter needs a read-only Proxmox API token; until it is configured the
role skips the install and ProxmoxExporterDown fires. To set it up:

1. On the Proxmox host (as root), create a read-only token:
   ```
   pveum user add pve-exporter@pam
   pveum aclmod / -user pve-exporter@pam -role PVEAuditor
   pveum user token add pve-exporter@pam monitoring --privsep 0
   ```
   The last command prints the token **value** once — copy it.
2. Add it as a GitHub Actions repo secret named `PVE_EXPORTER_TOKEN` (the token
   value only). The deploy workflow passes it to Ansible, which renders
   `/etc/prometheus-pve-exporter/pve.yml` (0600). Re-run the host-node deploy.
