# Nodes — VM/host alerts

Covers: NodeExporterDown, NodeFilesystemLowSpace, NodeDiskWillFillIn7Days,
NodeFilesystemInodesLow, NodeHighMemoryUsage, NodeLoadAverageHighNormalizedPerCore,
NodeOOMKills, NodeClockNotSynced, NodeTCPRetransmitRateHigh, NodeFilesystemDeviceError,
NodePrimaryInterfaceDown

## Diagnosis
```bash
ssh <user>@<vm-ip>
df -h /                      # space
df -i /                      # inodes (df lies when inodes are gone)
free -h; uptime              # memory / load
systemctl --failed           # broken units
sudo dmesg -T | grep -i oom  # OOM history
sudo du -x -d1 -h / | sort -rh | head   # what's eating the disk
```

## Common fixes
- Disk/inodes: `sudo journalctl --vacuum-size=50M`, `sudo docker image prune -af`,
  `sudo k3s crictl rmi --prune` (k3s nodes), `sudo apt-get clean`, then hunt big dirs.
- Clock: `sudo systemctl restart systemd-timesyncd` (or chrony); verify `timedatectl`.
- OOM: identify the hog with the OOMKill timestamp in dmesg, raise its memory
  limit (k8s) or stop it. Repeat OOMs = right-size properly.
  Check `constraint=` in the oom-kill line: `CONSTRAINT_MEMCG` = container hit
  its k8s memory limit (pod restarts, app keeps running) — raise that
  container's limit; host-level OOM means the node itself is short.
- Interface/netdev errors: check the Proxmox host NIC and VLAN before the VM.
- media-server load bursts: `ps aux --sort=-%cpu` usually shows
  `/usr/lib/jellyfin-ffmpeg/ffmpeg ... thumbnail=n=24` — Jellyfin's chapter-image
  extraction on newly downloaded media. Since 2026-09-29 this is throttled via
  `EncodingThreadCount` = 4 (of 6 cores) in `/opt/jellyfin/config/encoding.xml`
  (hostPath `/opt/jellyfin`, restart the jellyfin pod to reload); VAAPI handles
  playback transcodes, so the cap only limits CPU ffmpeg bursts. If it fires
  again, check that file wasn't reset by a Jellyfin settings change.

## Escalation
If the VM is unreachable: Proxmox UI console -> check qm status; last resort
stop/start from the host.

- **rx_dropped on every node (~2 packets/s, identical everywhere)** is normal:
  layer-2 broadcasts Linux has no handler for, e.g. IEEE 1905.1 topology
  discovery from the TP-Link mesh/extender (`b8:fb:b3:…`) and a switch's
  loop-detection frames. Only worry if one node's drops rise above the others.
- NodeTCPRetransmitRateHigh needs both >5% retransmits and >1 retransmitted
  segment/s for 10m; percentage alone was noise on the quiet gateway.
