# ArgoCD & Alertmanager — GitOps and notification alerts

Covers: ArgoCDApplicationOutOfSync, ArgoCDApplicationUnhealthy, ArgoCDComponentsDown,
AlertmanagerDown, AlertmanagerConfigReloadFailed, AlertmanagerNotificationsFailingToSend,
AlertmanagerNotificationRequestsFailingAtTheHTTPLevel, AlertmanagerHighNotificationLatency,
AlertmanagerClusterUnhealthy, AlertmanagerFailedPeersInCluster,
AlertmanagerInvalidAlertsBeingReceived, AlertmanagerAggregationGroupCreationFailures,
AlertmanagerSilenceGCErrors, Watchdog

## Diagnosis
```bash
sudo k3s kubectl get applications.argoproj.io -n argocd
sudo k3s kubectl logs -n argocd deploy/argocd-repo-server --tail=30
sudo k3s kubectl logs -n monitoring deploy/alertmanager --tail=30
curl -s http://192.168.10.203:30302/alertmanager   # alert-forwarder reachable?
```

## Notes
- **How loud an alert is** (roles/alertmanager, alert-forwarder):
  critical -> Discord with @here, repeated hourly; warning -> Discord without
  a mention, grouped by alertname, repeated every 12h; resolved -> plain.
  Severity `none` is never posted.
- **Dead man's switch:** `Watchdog` always fires. Alertmanager sends it to
  healthchecks.io (check `homelab-alertmanager`, period 5m, grace 5m) every
  minute. If healthchecks.io emails "DOWN", the alert path itself is broken
  (Prometheus, Alertmanager or monitoring-server); Discord will be silent, so
  check those first. The ping URL is the `HEALTHCHECKS_PING_URL` secret.
- **CI deploys silence warnings** (not criticals) for up to 45 minutes and lift
  the silence when Ansible ends. See active silences:
  `curl -s http://192.168.10.203:9093/api/v2/silences | jq '.[] | select(.status.state=="active")'`
- ArgoCD sync policy on the apps: `automated: {prune: true, selfHeal: false}` —
  auto-sync fires on NEW git revisions, but live drift (manual kubectl edits)
  is NOT auto-reverted and shows up as OutOfSync until git catches up.
- ArgoCDApplicationOutOfSync where live is the DESIRED state (e.g. a hotfix
  applied via kubectl): fix is to get the change into git and push — a
  kubectl-revert of live re-breaks the cluster, and pushing any unrelated
  commit to the app dir first triggers an automated sync of the OLD manifest.
- ArgoCDApplicationUnhealthy with health=Progressing right after an Image
  Updater deploy is expected: big images pull for minutes (tracearr ~900MB
  pulled for ~3m on 2026-10-04). The rule's `for: 10m` filters these out —
  a firing alert means the rollout is genuinely stuck. Check pod events:
  `sudo k3s kubectl get events -n <app-ns> --sort-by=.lastTimestamp`.
- Alertmanager down = NO notifications from ANY rule (silent failure mode).
  The dead-man's switch is the designed backstop for exactly this alert.
- Notifications failing -> check the alert-forwarder pod and the Discord
  webhook URL it posts to.
