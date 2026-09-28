# Disaster-recovery rebuild runbook

Scenario: the Proxmox host (192.168.10.250, node `rami`) died. Backups exist
as nightly vzdump archives in `tank/backup/dump` (keep 7 daily + 4 weekly).
Time target: an afternoon. Read this fully before starting.

## 0. Assumptions
- `tank` ZFS pool survived (data disks separate from boot disk). If the pool
  is gone, restore from off-site copies — otherwise this is a full rebuild,
  not a restore.
- Terraform state lives in git (`Terraform/terraform.tfstate`).

## 1. Rebuild the host
1. Install Proxmox VE (same hostname `rami`, same management IP 192.168.10.250).
2. Import the data pool: `zpool import -f tank` (or recreate + restore from
   off-site if truly lost).
3. Recreate the backup storage: `zfs create tank/backup`; add to
   `/etc/pve/storage.cfg`:
   ```
   dir: backup
   \tpath /tank/backup
   \tcontent backup
   ```
4. Re-authorize your SSH key for root.

## 2. Restore the VMs (order matters)
```bash
for id in 115 505 511 911; do
  dump=$(ls -t /tank/backup/dump/vzdump-qemu-$id-*.zst | head -1)
  qmrestore "$dump" $id --storage local-lvm
done
# VM 100 (owner's macOS test VM) is intentionally NOT restored from backup.
qm start 115   # git-k3s first (control plane + CI runner)
qm start 505   # gateway (DNS for everything else)
qm start 511   # monitoring
qm start 911   # media
```
VM specs live in `Terraform/terraform.tfvars` — after restore, verify memory
matches (`qm config <id> | grep memory`).

## 3. Reconcile infrastructure as code
Nothing to apply if state matches git — verify:
```bash
cd Terraform && terraform init && terraform plan -input=false -no-color
```
If the host was rebuilt from scratch (state lost), import each VM instead of
letting Terraform create them:
```bash
terraform import 'module.proxmox_vms["gateway"].proxmox_virtual_environment_vm.vm' 505
# repeat: media=911, monitoring=511, github=115
```

## 4. Re-run configuration management
```bash
ansible-playbook -i Ansbile/inventory.ini Ansbile/gateway-server.yml --vault-password-file ~/.vault_pass
ansible-playbook -i Ansbile/inventory.ini Ansbile/monitoring-server.yml --vault-password-file ~/.vault_pass
ansible-playbook -i Ansbile/inventory.ini Ansbile/media-server.yml --vault-password-file ~/.vault_pass
ansible-playbook -i Ansbile/inventory.ini Ansbile/git-k3s-server.yml --vault-password-file ~/.vault_pass
```
This rebuilds: AdGuard (systemd), adguard-exporter (systemd,
/opt/adguard-exporter), the k3s cluster bootstrap, ArgoCD + Image Updater,
istio, MetalLB, calico, cert-manager, ingress-nginx, tempo, promtail and
renders Prometheus/Loki/Alertmanager configs. Note: ufw, docker and the
adguard-exporter systemd units are current live state; codify anything you
had to fix by hand (see AGENTS.md conventions).

## 5. GitOps takes over
ArgoCD auto-syncs media/monitoring/network from `Ansbile/argocd-apps/` —
verify all three Applications reach Synced+Healthy:
```bash
sudo k3s kubectl get applications.argoproj.io -n argocd
```

## 6. Verify
- [ ] All 4 nodes `Ready`, same k3s version (`kubectl get nodes`)
- [ ] Probes green: all 20 targets `probe_success == 1`
- [ ] ArgoCD apps Synced + Healthy
- [ ] Alert path works: stop jellyfin, expect the alert in Discord
- [ ] Next nightly backup lands in `/tank/backup/dump`

## If the host is truly dead and dumps are gone
Off-site copies (rclone target) -> `qmrestore` on the new host. If those are
gone too: rebuild VMs from Terraform (fresh disks), re-run Ansible (it
installs everything), and restore app DATA from whatever application-level
copies exist. This is why the off-site leg of 3-2-1 matters.
