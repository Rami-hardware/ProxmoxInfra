# Hardware & app exporters — SMART / ZFS / scraparr / qBittorrent / GPU

Covers: Smart*, Zfs*, Scraparr*, Qbit*, IntelGpu*, CertManagerCertNotReady,
BlackboxExporterDown

## Quick pointers
- SMART (host disks): `smartctl -a /dev/sdX` on the Proxmox host; reallocated
  or pending sectors > 0 = plan replacement, run a long self-test.
- ZFS: `zpool status tank`, `zpool list` on the host. DEGRADED = act now.
- qBittorrent: Web UI at 192.168.10.201:8080; stalled downloads usually mean
  dead torrents or tracker/network issues (check port forwarding).
- scraparr: per-arr health — Sonarr/Radarr queues are app-side
  (Activity > Queue); Prowlarr indexer failures = indexers rate-limiting you.
- Intel GPU: sustained >90% engine busy or power draw = check active Jellyfin
  transcodes; the iGPU idles at ~100% RC6 residency.
- cert-manager: `kubectl describe certificate -A` and CertificateRequest events.
