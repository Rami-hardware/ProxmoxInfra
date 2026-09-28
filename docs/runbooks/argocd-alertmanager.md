# ArgoCD & Alertmanager — GitOps and notification alerts

Covers: ArgoCDApplicationOutOfSync, ArgoCDApplicationUnhealthy, ArgoCDComponentsDown,
AlertmanagerDown, AlertmanagerConfigReloadFailed, AlertmanagerNotificationsFailingToSend,
AlertmanagerNotificationRequestsFailingAtTheHTTPLevel, AlertmanagerHighNotificationLatency,
AlertmanagerClusterUnhealthy, AlertmanagerFailedPeersInCluster,
AlertmanagerInvalidAlertsBeingReceived, AlertmanagerAggregationGroupCreationFailures,
AlertmanagerSilenceGCErrors

## Diagnosis
```bash
sudo k3s kubectl get applications.argoproj.io -n argocd
sudo k3s kubectl logs -n argocd deploy/argocd-repo-server --tail=30
sudo k3s kubectl logs -n monitoring deploy/alertmanager --tail=30
curl -s http://192.168.10.203:30302/alertmanager   # alert-forwarder reachable?
```

## Notes
- ArgoCD self-heal + prune is ON: if live state drifted, diff in the UI before
  force-syncing — manual kubectl changes will be reverted by design.
- Alertmanager down = NO notifications from ANY rule (silent failure mode).
  The dead-man's switch is the designed backstop for exactly this alert.
- Notifications failing -> check the alert-forwarder pod and the Discord
  webhook URL it posts to.
