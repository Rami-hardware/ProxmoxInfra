---
name: alertops
description: Use when working with tools/alertops-mcp/, the alert-fixer agent, Alertmanager remediation allowlists, or the MCP server that investigates and closes alerts.
---

## Alert Automation (`tools/alertops-mcp/`, `.claude/agents/alert-fixer.md`)

- `alertops-mcp`: Python MCP server (registered in `.mcp.json`, stdio, own `.venv`). It takes alerts from Alertmanager → investigation (Prometheus/Loki/kubectl-over-ssh/host checks) → allowlisted remediation → verification → close with root cause to Discord via alert-forwarder. The server enforces the order: no remediation without a recorded finding, and no close without a fresh passing verification after the last action. It also applies rate limits/cooldowns and has a kill switch (`~/.local/state/alertops/DISABLE_REMEDIATION`).
- Remediation allowlists live in `tools/alertops-mcp/config.yaml` (hosts → systemd units/containers, k8s namespaces). If you rename a service/unit in Ansible, update the allowlist too.
- Tests: `cd tools/alertops-mcp && .venv/bin/pip install -e ".[test]" && .venv/bin/pytest -q` (fakes, no network).
- `scripts/alert-fixer.sh` (cron wrapper, installed to `~/bin`) runs the `alert-fixer` agent headless.
