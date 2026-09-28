# Loki & Promtail — log pipeline + log-based alerts

Covers: LokiIngesterPushGRPCErrors, LokiHighRequestErrorRate5xx, LokiPushFailures,
LokiIngesterWALDiskUsageHigh, LokiWALDiskFullFailures, LokiIngesterChunkFlushFailures,
LokiQuerySchedulerQueueBackingUp, LokiRateStoreRefreshFailures, LokiRingMemberUnhealthy,
LokiCompactorNotRunningRetentionFailing, LokiProcessDown, PromtailDroppedLogEntries,
PromtailDroppedBytes, PromtailBatchRetriesClimbing, PromtailRequestErrors,
PromtailProcessExporterDown, LogErrorRateSpike, TLSOrCertificateErrorInLogs,
SonarrRadarrDownloadFailures, TempoLogsSilent

## Diagnosis
```bash
sudo k3s kubectl get pods -n monitoring -l app=loki
sudo k3s kubectl logs -n monitoring deploy/loki --tail=30
curl -s http://192.168.10.203:3100/ready
sudo du -sh /opt/docker/loki-data            # on monitoring-server (hostPath PV)
sudo k3s kubectl logs -n monitoring -l app=promtail --tail=30 | grep -i error
```

## Common fixes
- Push failures / promtail 4xx: entry too far behind after downtime — the stale
  batches drain on their own ("final error sending batch" = dropped by design);
  a promtail pod restart clears positions faster.
- WAL disk usage: the data PV lives on the monitoring VM disk — same cleanup
  playbook as any disk alert.
- Log-based alerts (error spike, TLS errors, Sonarr/Radarr failures) come from
  Loki's RULER (loki-rules.yml.j2), not Prometheus.
