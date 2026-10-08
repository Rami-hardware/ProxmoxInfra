# Istio & Tempo — mesh and tracing alerts

Covers: IstioAgentCertificateExpiringSoon, IstioEnvoyProxyNotLive,
IstioEnvoyConnectionFailuresToXdsGrpc, IstiodConnectionTerminations,
IstioEnvoyWatchdogMiss, IstioEnvoyWatchdogMegaMiss, IstioXDSConfigPushFailuresPending,
IstioEnvoyTotalConnectionsAbnormallyHigh, IstioEnvoyMemoryGrowingUnbounded,
TempoDown, TempoDistributorPushFailures, TempoIngesterTracesDropped,
TempoFlushFailures, TempoCompactorFailures, TempoQueryErrors, TempoHighIngestionLatency

## Diagnosis
```bash
sudo k3s kubectl get pods -n istio-system
sudo k3s kubectl logs -n istio-system deploy/istiod --tail=30
sudo k3s kubectl logs -n <ns> <pod> -c istio-proxy --tail=30
curl -s http://192.168.10.203:3100/ready 2>/dev/null   # (tempo is on git-k3s)
sudo k3s kubectl logs -n istio-system deploy/tempo --tail=30
```

## Notes
- istiod is pinned to git-k3s-server (nodeSelector) — a control-plane reboot
  restarts the whole mesh control plane. Sidecars reconnect automatically.
- Sidecar cert rotation is automatic (24h lifetime); the alert fires only if
  expiry keeps dropping without renewal (stuck rotation).
- Tempo storage: if the tempo-storage PVC trends full, reduce trace volume or
  compaction retention in its manifest.
- Watchdog misses on **many pods across several nodes at the same time** mean
  the Proxmox host was CPU-starved (12 cores, ~11 vCPUs allocated), not that a
  sidecar is broken. Usual cause: a CI full redeploy (see `gh run list`) or a
  backup. Check `sum(increase(envoy_server_watchdog_miss[2m]))` against host-node
  CPU. Only misses that keep growing on ONE pod are worth acting on: check that
  pod's CPU throttling (`container_cpu_cfs_throttled_periods_total{container="istio-proxy"}`)
  and restart it if the proxy is wedged. (2026-10-08: 24 misses on 15 pods
  during two back-to-back CI deploys; the threshold was raised to >10/15m for 10m.)
