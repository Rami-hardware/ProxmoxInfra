# alertops-mcp

MCP server that gives an AI agent a **guarded** path from a firing Alertmanager alert to a closed incident:

```
list_alerts → get_alert_context → start_investigation → (read-only investigation)
  → record_finding → remediate (allowlisted) → verify_resolution → close_incident
                                      └── or escalate_incident / post_postmortem
```

The agent gets typed tools instead of a shell. The server enforces the workflow. The prompt only asks for it.

## Guarantees

| Gate | Enforced by |
|---|---|
| No remediation before a diagnosis | `record_finding` required first (`store.require_can_remediate`) |
| Only known-safe actions | 7 typed actions, each with an allowlist: namespaces, per-host systemd units / containers. `host-node` (Proxmox) is read-only |
| No restart loops | max actions per incident (3), per-target cooldown (15 min), global cap (10/h) |
| Kill switch | `touch ~/.local/state/alertops/DISABLE_REMEDIATION` or `remediation.enabled: false` → read-only mode |
| Prechecks | workload must exist; pod must be controller-owned before delete; journal vacuum has a size floor |
| No close without proof | `close_incident` needs a **passing, fresh (<30 min) verification taken after the last action** |
| Verification is real | the alert's `ALERTS` series must be absent for the whole stability window (3 min) after the last action, not just "not in Alertmanager right now" (that lags by `resolve_timeout`). Optional `health_check_promql` must return data |
| Root cause required | `root_cause` ≥ 30 chars, posted to Discord with the fix, actions, and verification |
| Audit | every finding/action/verification/close in SQLite + `audit.jsonl` under `state_dir` |
| No injection | values validated by regex, commands built as argv, shell-quoted with `shlex.join`, run via `ssh` without a local shell. Secrets aren't readable via `k8s_get` |

Things the server **cannot** do: terraform, git, editing files, deleting PVs/PVCs/data, silencing alerts, touching the Proxmox host beyond read-only checks.

## Tools

- **Ingest:** `list_alerts`, `get_alert_context` (rule expr + current value + local runbook), `start_investigation`, `record_finding`, `get_incident`, `list_incidents`
- **Investigate (read-only):** `query_prometheus`, `query_prometheus_range`, `query_loki`, `k8s_get`, `k8s_describe`, `k8s_logs`, `k8s_events`, `k8s_top`, `host_check` (disk, inodes, memory, load, top_cpu/mem, failed_units, unit_status, journal, journal_errors, docker_ps, du, dmesg, zpool_status)
- **Remediate (all take `incident_id`, `reason`, `dry_run`):** `restart_k8s_workload`, `delete_k8s_pod`, `restart_systemd_unit`, `restart_docker_container`, `prune_container_images`, `vacuum_journal`, `reload_prometheus`
- **Finish:** `verify_resolution`, `close_incident`, `escalate_incident`, `post_postmortem`

Discord delivery goes through the existing `alert-forwarder`. If Alertmanager hasn't sent RESOLVED yet, the report is attached via `/notes` and rides that message. Otherwise it's a standalone `/report`.

## Setup

```bash
cd tools/alertops-mcp
python3 -m venv .venv && .venv/bin/pip install -e .
```

Registered for Claude Code in the repo's `.mcp.json` (stdio). Other clients: run `alertops-mcp --config config.yaml`
(stdio) or `alertops-mcp --http --port 8765` (streamable HTTP, binds 127.0.0.1).

Requirements on the machine running it: network access to the monitoring VM, and the SSH key in `config.yaml`
authorized on the inventory hosts with passwordless `sudo -n`. kubectl runs on `git-k3s-server` over ssh.

Adding an allowed action target = edit `config.yaml` (`hosts.remediation.<host>`, `kubernetes.remediation_namespaces`).
Adding a new *kind* of action = a method in `service.py` that goes through `_remediate()`, a tool in `server.py`, and a test.

## Tests

```bash
.venv/bin/pip install -e ".[test]" && .venv/bin/pytest -q
```

Unit tests use fakes (no network). They cover the state machine, every safety gate, input validation, and the MCP
protocol surface via an in-memory client.
