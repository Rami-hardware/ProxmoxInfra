# CI runners — offline runner, job lost with its runner

Covers: the Discord messages from `.github/workflows/runner-health.yml`
("CI runner offline" / "back online") and `runner-retry.yml` ("CI job retried
(runner lost)"). These are GitHub Actions checks, not Prometheus alerts.

Runners: `ci-runner-<n>-a` / `-b` = two instances on LXC `ci-runner-<n>`
(vmid 205+, `.205`+), user `runner-a` / `runner-b`; label `lxc`. Installed by
`ci-runners.yml` / `roles/ci_runner`.

## Diagnosis
- Which runners: repo → Settings → Actions → Runners, or
  `gh api repos/Rami-hardware/ProxmoxInfra/actions/runners -q '.runners[]|"\(.name) \(.status)"'`.
- Both instances of one LXC offline = the container is down:
  `pct status <vmid>` on the Proxmox host.
- One instance offline = its service:
  `ssh root@192.168.10.<ip> 'systemctl status "actions.runner.*"'`, and
  `journalctl -u "actions.runner.*" -n 50`.
- Disk/memory: the LXCs run node-exporter (`instance=ci-runner-N`), so the
  usual node disk/memory alerts cover them. Disk full stops jobs:
  `df -h /` on the LXC (the cleanup timer
  `ci-runner-cleanup.timer` prunes `_work` and caches).

## Fixes
- Container down: `pct start <vmid>`. The runners start with it.
- Service dead: `systemctl restart "actions.runner.*"` on the LXC.
- Runner removed from GitHub (shows nowhere, or "not configured"): re-run the
  playbook for that host — it registers missing instances with the
  `RUNNER_ADMIN_TOKEN` secret (CI) or `vault_github_runner_pat` (by hand).
  An unregistered instance needs `rm /home/runner-<x>/actions-runner/.runner`
  first if the file is still there:
  `ansible-playbook -i Ansbile/inventory.ini Ansbile/ci-runners.yml --limit ci-runner-<n> --vault-password-file ~/.vault_pass`.
- Container rebuilt: pin its new host key in `.github/ssh_known_hosts`
  (`ssh-keyscan -t ed25519 <ip>`, compare with the console) before CI can reach it.

## Retries
`runner-retry.yml` re-runs the failed jobs of a pipeline run **once** when a
job's annotation says the runner "lost communication" or got a shutdown
signal. Real failures are never retried. On `main` the re-run waits for the
Production approval again. If the retry fails too, treat it as a real failure.

## Setup
`runner-health.yml` needs repo secret `RUNNER_STATUS_TOKEN`: a fine-grained
PAT for this repo with **Administration: Read-only**. Without it the check
only prints a warning.
