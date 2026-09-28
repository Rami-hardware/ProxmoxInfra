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
- Interface/netdev errors: check the Proxmox host NIC and VLAN before the VM.

## Escalation
If the VM is unreachable: Proxmox UI console -> check qm status; last resort
stop/start from the host.
