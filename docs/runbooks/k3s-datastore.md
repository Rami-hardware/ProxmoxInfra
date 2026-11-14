# k3s datastore — snapshots and restore

Covers: K3sDatastoreSnapshotStale, K3sDatastoreSnapshotMissing

The whole cluster state (every object, Secret and ArgoCD Application) lives in
one sqlite file on git-k3s-server: `/var/lib/rancher/k3s/server/db/state.db`.
`k3s-db-snapshot.timer` (roles/k3s_server) copies it nightly at ~02:30 UTC
with sqlite's online backup API, checks the copy's integrity, compresses it
and keeps 7 in `/var/backups/k3s/` with the server `token`. vzdump backs up
the VM disk, so the snapshots ride along; a raw `state.db` copied mid-write
(by vzdump or after a hard reboot) can be torn, these can't.

## Diagnosis (alert fired)
```bash
ssh github@192.168.10.204
systemctl status k3s-db-snapshot.timer k3s-db-snapshot.service
journalctl -u k3s-db-snapshot.service -n 50
sudo ls -lh /var/backups/k3s/
cat /var/lib/node_exporter/textfile_collector/k3s_db_snapshot.prom
df -h /
```
- `integrity check failed`: the live database is damaged. Do not let older
  good snapshots rotate out — copy them off the VM now, then plan a restore.
- Missing metric but snapshots exist: node-exporter lost the textfile
  collector arg (k3s_apps node-exporter DaemonSet).
- Run one by hand: `sudo systemctl start k3s-db-snapshot.service`.

## Restore (control plane broken, datastore corrupt)
This rewinds the cluster to the snapshot's time. Objects created after it are
lost; ArgoCD re-syncs apps from git, and a full CI run re-applies what Ansible
owns (Helm releases, the cloudflared token Secret).
```bash
ssh github@192.168.10.204
sudo systemctl stop k3s
cd /var/lib/rancher/k3s/server/db
sudo mkdir -p /root/state-broken && sudo mv state.db state.db-wal state.db-shm /root/state-broken/ 2>/dev/null
snap=$(sudo ls -t /var/backups/k3s/state-*.db.zst | head -1)
sudo zstd -d "$snap" -o state.db
sudo cmp /var/backups/k3s/token /var/lib/rancher/k3s/server/token || sudo install -m 600 /var/backups/k3s/token /var/lib/rancher/k3s/server/token
sudo systemctl start k3s
sudo k3s kubectl get nodes
sudo k3s kubectl -n argocd get applications
```
Then run the pipeline with **full deploy** (Actions → Homelab CI/CD → Run
workflow) so Ansible re-applies everything it owns.
