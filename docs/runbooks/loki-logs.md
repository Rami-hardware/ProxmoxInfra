# Loki & Alloy — log pipeline + log-based alerts

Covers: AlloyDroppedLogEntries, AlloyLokiWriteRetries, AlloyDown, LokiIngesterPushGRPCErrors, LokiHighRequestErrorRate5xx, LokiPushFailures,
LokiIngesterWALDiskUsageHigh, LokiWALDiskFullFailures, LokiIngesterChunkFlushFailures,
LokiQuerySchedulerQueueBackingUp, LokiRateStoreRefreshFailures, LokiCompactorNotRunningRetentionFailing, LokiProcessDown, LogErrorRateSpike, TLSOrCertificateErrorInLogs, LogPipelineBroken,
SonarrRadarrDownloadFailures, TempoLogsSilent

## Diagnosis
```bash
sudo k3s kubectl get pods -n monitoring -l app=loki
sudo k3s kubectl logs -n monitoring deploy/loki --tail=30
curl -s http://192.168.10.203:3100/ready
sudo du -sh /opt/docker/loki-data            # on monitoring-server (hostPath PV)
sudo k3s kubectl logs -n monitoring -l app=alloy --tail=30 | grep -i error
# Alloy UI (pipeline graph, per-component health): http://<node-ip>:12345
```

## Common fixes
- Push failures / Alloy 4xx: entry too far behind after downtime — the stale
  batches drain on their own ("final error sending batch" = dropped by design);
  an Alloy pod restart clears it faster. Alloy keeps read positions in
  /var/lib/alloy on each node and starts new files at the end, so a restart
  does not re-send old lines.
- WAL disk usage: the data PV lives on the monitoring VM disk — same cleanup
  playbook as any disk alert.
- Log-based alerts (error spike, TLS errors, Sonarr/Radarr failures) come from
  Loki's RULER (loki-rules.yml.j2), not Prometheus.

## Notes
- **Log alerts are Prometheus alerts** (group `logs` in prometheus-rules).
  Loki's ruler evaluates the LogQL as recording rules every minute
  (`log:lines:count5m`, `log:error_lines:count5m`, ...) and remote-writes them
  to Prometheus. Query them there, e.g. `topk(5, log:error_lines:count5m)`.
- **LogPipelineBroken**: `log:lines:count5m` stopped arriving. Check, in order:
  Alloy pods, the Loki pod, Loki logs for `remote write` errors, and
  Prometheus' remote-write receiver (`--web.enable-remote-write-receiver`).
  While it fires, every log alert is blind.
