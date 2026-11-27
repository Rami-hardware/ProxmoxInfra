---
name: ansible-homelab
description: Use when editing anything under Ansbile/ (roles, playbooks, inventory, group_vars, templates), or when running ansible-playbook, ansible-lint, or working with the vault. Covers role conventions, the changed-roles CI detection, and alerting rules placement.
---

## Ansible (`Ansbile/`)

- Inventory: `inventory.ini` (groups = `gateway-vm`, `media-vm`, `monitoring-vm`, `git-k3s-server-vm`, `host-node`). Group names must match `group_vars/<group>.yml` filenames.
- Playbooks: one per host (`gateway-server.yml`, `media-server.yml`, `monitoring-server.yml`, `git-k3s-server.yml`, `ci-runners.yml`, `host-node.yml` — the last is the Proxmox host itself, managed narrowly: SSH keys, chrony NTP sources, node/zfs/pve exporters).
- 19 roles under `Ansbile/roles/`. In CI all host playbooks run in parallel (see CI/CD).
- Terraform runs in CI only when its files changed (`changes` flags `terraform` for `Terraform/` and `cloudflare` for `Terraform/cloudflare/`): fmt/validate in Testing, VM plan + destroy guard (applied on main after approval) and Cloudflare plan/apply/tunnel token in Deploy. Schedule and manual full runs do all of it. The gateway `--check --diff` dry run only runs on `development` (staging's real deploy is the test), limited to the changed gateway roles. Ansible runs with `ANSIBLE_PIPELINING=True`.
- **CI runs only the roles whose files changed** since the branch's last successful pipeline run (`.github/scripts/detect-changed-hosts.sh`). Every playbook tags each role with its own name (`- { role: x, tags: [x] }` — keep that format, the script parses it), and a change under `roles/<r>/` runs `ansible-playbook --tags r` on every host whose playbook lists `r` (a `common` change runs only `common`). A role can go finer by splitting `tasks/main.yml` into `tasks/<part>.yml` imported with `tags: [<role>_<part>]` (k3s_apps does, one file per component): a changed `tasks/<part>.yml` or a template/file named in only such parts runs just those parts; `main.yml`, defaults, handlers, or a template no part names run the whole role. Parts must not use registers/facts from each other. `apps/` → `k3s_apps`; `group_vars/all/local_dns.yml` → `adguard` + `unbound`. A host's playbook or `group_vars/<host>.yml` runs that whole host. `vault.yml`, inventory, `requirements.yml`, `.github/`, or a role in no playbook run everything; schedule and manual dispatch always run everything. The run summary of `Detect Changed Hosts` lists the roles per host. **Never use a fact/`register` from another role** — with `--tags` that role may not run.
- Secrets: `group_vars/all/vault.yml` is fully vault-encrypted (plain vars go in other files under `group_vars/all/`, e.g. `local_dns.yml`). Vault password via `--vault-password-file ~/.vault_pass` (CI writes it from `ANSIBLE_VAULT_PASSWORD` secret). Never commit plaintext secrets — GitHub push protection blocks known token types.

### Conventions (enforced — match existing code)

- **FQCN always**: `ansible.builtin.template`, `community.general.*` — no short module names.
- **Role vars prefixed** `<role_name>_` (e.g. `k3s_server_version`, `grafana_data_dir`).
- **All config rendered from Jinja2 templates** (`*.yml.j2`) — no inline hardcoded content in tasks.
- **Helm releases** in `k3s_apps` use `kubernetes.core.helm` with every chart version pinned (`k3s_apps_*_chart_version`) and the `helm-diff` plugin (`/etc/helm/plugins`), so a release only upgrades when its rendered manifests change. Bump chart versions on purpose; never go back to shell `helm upgrade --install`.
- **No moving image tags** (`:latest`, `:alpine`) in Ansible templates: pin a version (bump it on purpose). ArgoCD apps may use `:latest` in `kustomization.yaml` only because Image Updater pins the digest in `.argocd-source-*.yaml` — but stateful apps whose next major can change their data or config format follow one major only (Prometheus `v3`, Loki `3`, Jellyfin `12`, Redis `8-alpine`, TimescaleDB `pg18` = digest of the major tag; Grafana `13.x` = `semver` + `allow-tags`, set in the `*-app.yaml` annotations). Bump a major there on purpose. Every image under `argocd-apps/` must be in its app's `image-list`, or it is never updated. TimescaleDB's pod runs `ALTER EXTENSION … UPDATE` in a postStart hook after an image change. AdGuard is not a pod (systemd on the gateway, `adguard_version`, updated by Renovate). alert-forwarder deploys `:app-<content hash>` (see build-image.yml).
- **IPs referenced via `hostvars[host]['ansible_host']`** from inventory — single source of truth, never hardcode IPs.
- Command/shell tasks need explicit `changed_when` / `failed_when`.
- Alerting: all Prometheus-evaluated rules live in `roles/prometheus/templates/prometheus-rules.yml.j2` (Alertmanager → alert-forwarder → Discord). Log-based alerts live there too (group `logs`): Loki's ruler only runs LogQL **recording** rules (`roles/loki/templates/loki-rules.yml.j2`, metrics named `log:*`) and remote-writes them to Prometheus. Loki itself sends no alerts. Grafana keeps NO alert rules — never add alerts in the Grafana UI.
- SRE docs: SLOs (99.5% local/public, 99.9% DNS, 14d window) with multiwindow burn-rate alerts live in the rules file; every alert carries a `runbook_url` into `docs/runbooks/`. DR: `docs/rebuild.md`. Incidents: `docs/incident-template.md`. Keep runbooks updated after incidents.

### Commands

```bash
ansible-galaxy collection install -r Ansbile/requirements.yml
ansible-playbook -i Ansbile/inventory.ini Ansbile/gateway-server.yml --syntax-check --vault-password-file ~/.vault_pass
ansible-lint Ansbile/
ansible-playbook -i Ansbile/inventory.ini Ansbile/gateway-server.yml --check --diff --vault-password-file ~/.vault_pass
```

(`--check` dry run is only verified on the gateway playbook.)
