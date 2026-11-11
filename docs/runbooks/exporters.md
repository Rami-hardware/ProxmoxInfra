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
