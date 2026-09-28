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
