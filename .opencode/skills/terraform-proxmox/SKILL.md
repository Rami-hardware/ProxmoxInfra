---
name: terraform-proxmox
description: Use when editing anything under Terraform/, provisioning or changing Proxmox VMs and LXC containers, touching terraform.tfvars or terraform.tfstate, or running terraform plan/apply for this homelab.
---

## Terraform (`Terraform/`)

- Provider `bpg/proxmox` pinned `~> 0.70.1`. No `required_version`. No remote backend — **state (`terraform.tfstate`) is committed to git**.
- `Terraform/.terraform/` is gitignored — provider binaries were once committed (81MB, several stale versions); never re-add them. CI installs providers via the filesystem mirror action.
- VMs defined as a `map(object)` in `terraform.tfvars` (keys: `gateway`, `media`, `monitoring`, `github`). Map keys are state addresses: **renaming a key destroys the VM**. The VM module has `prevent_destroy = true`: a plan that would destroy or replace a VM errors out (remove it in a deliberate commit to really destroy one). Disk size is ignore_changes — resize in Proxmox (`qm resize`), then update tfvars.
- LXC containers: `containers` map (keys `ci_runner_1`..`ci_runner_3`) → `modules/proxmox_lxc` (unprivileged, nesting only — no Docker on the runners). Same key-rename rule. The Ubuntu template must exist on the host first: `pveam update && pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst`.
- Host RAM is the tight resource (33.6 GB, VMs pin most of it; media's GPU passthrough pins all of its RAM). Check `node_memory_MemAvailable_bytes{instance="host-node"}` before adding guests.
  - A key rename makes CI's plan show destroy + recreate and block. Move the state by hand first (`terraform state mv 'module.proxmox_vms["old"]' 'module.proxmox_vms["new"]'`) and commit the state.
- `lifecycle.ignore_changes` (in `modules/proxmox_vm/main.tf`) covers `disk`, `initialization`, `clone`, `hostpci`, `cpu` and more — don't remove.
- **CI applies VMs/LXCs on `main` only, after the Production approval, and only when that deploy contains a Proxmox Terraform code change** (`Terraform/*.tf`, `*.tfvars`, `modules/` → `changes` output `terraform_apply`). Drift (hand edits in Proxmox), scheduled/full runs and `terraform.tfstate`-only commits plan and warn (`### ⚠️ Terraform drift — NOT applied`) but never modify or delete anything. `deploy.yml`: `tf_plan` runs before the approval (full diff in the run summary — read it before approving), a destroy/replace fails the pipeline; `tf_apply` (after `gate`, on an `lxc` runner because a VM change can reboot git-k3s) re-plans, refuses if the plan differs from the reviewed one (`.github/scripts/tf-plan-fingerprint.sh`), applies with `-parallelism=1`, and commits `terraform.tfstate` back to main **and** staging (`github-actions[bot]`, pull before pushing). Staging only plans. Destroys/replaces stay manual.
- Manual apply requires `parallelism=1` (Proxmox API race conditions); `-target` per resource keeps the blast radius small. Commit `terraform.tfstate` afterwards.
- Provider values come from `TF_VAR_*` env vars (GitHub secrets) — never hardcode tokens. TLS to the Proxmox API is verified (no `insecure`): the runners trust the PVE cluster CA (`roles/ci_runner/files/pve-root-ca.crt`); a manual apply needs that CA trusted too. If the host's IP or name changes, fix `/etc/hosts` on it and run `pvecm updatecerts --force`, or the certificate stops matching.
- SSH is **key-only** everywhere (`roles/common` drop-in `00-hardening.conf`). Separate keys per consumer, managed by `roles/ssh_access` (first role in every playbook; public keys in its `files/<name>.pub`): `owner` (your desktop, alertops-mcp) and `ci` (secret `SSH_PRIVATE_KEY`). Revoke one by setting its `state: absent`. **The CI key is also ArgoCD's git key**: `k3s_apps` copies the runner's `~/.ssh/id_rsa` into the ArgoCD repo credentials and Image Updater's write-back secret, so whatever key `SSH_PRIVATE_KEY` holds must be a **writable deploy key** on the GitHub repo — rotate both together, or every app goes `ComparisonError` (nothing syncs, no image updates). Terraform's `SSH_PUBLIC_KEY` secret holds both public keys, one per line, for cloud-init on new guests. The `cipassword` values in tfvars are empty — cloud-init legacy, no live effect (`initialization` is ignore_changes).

### Commands (run from `Terraform/`)

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform plan -input=false -no-color -detailed-exitcode -out=tfplan
```
