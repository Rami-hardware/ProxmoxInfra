# Istio & Tempo — mesh and tracing alerts

Covers: IstioAmbientNodeAgentNotReady, IstioAgentCertificateExpiringSoon, IstioEnvoyProxyNotLive,
IstioEnvoyConnectionFailuresToXdsGrpc, IstiodConnectionTerminations,
IstioEnvoyWatchdogMiss, IstioEnvoyWatchdogMegaMiss, IstioXDSConfigPushFailuresPending,
IstioEnvoyTotalConnectionsAbnormallyHigh, IstioEnvoyMemoryGrowingUnbounded,
TempoDown, TempoDistributorPushFailures, TempoIngesterTracesDropped,
TempoFlushFailures, TempoCompactorFailures, TempoQueryErrors, TempoHighIngestionLatency

## Diagnosis
```bash
sudo k3s kubectl get pods -n istio-system
sudo k3s kubectl logs -n istio-system deploy/istiod --tail=30
sudo k3s kubectl get ds -n istio-system                 # ztunnel + istio-cni-node, one per node
sudo k3s kubectl logs -n istio-system ds/ztunnel --tail=30
sudo k3s kubectl logs -n media deploy/waypoint --tail=30
curl -s http://192.168.10.203:3100/ready 2>/dev/null   # (tempo is on git-k3s)
sudo k3s kubectl logs -n istio-system deploy/tempo --tail=30
```

## Notes
- Ambient mode, no sidecars. `media`, `monitoring` and `network` carry
  `istio.io/dataplane-mode=ambient` (set by roles/k3s_apps). ztunnel on each
  node does mTLS between mesh pods; `media` also has a waypoint proxy
  (`deploy/waypoint`) for L7 metrics and traces between Services.
- Pod-to-pod traffic is mTLS only when addressed to a Service (or pod IP);
  only Service traffic goes through the waypoint. Apps must call each other as
  `http://<app>.media.svc.cluster.local:<port>`, not the node IP: node
  IP:NodePort leaves the mesh as plain text.
  Check: `sum by (connection_security_policy) (rate(istio_tcp_connections_opened_total{reporter="destination"}[1h]))`.
- Ingress traffic goes straight to the pod (ingress-nginx is hostNetwork and
  outside the mesh), so it is plain text from the ingress and not traced by
  Istio. PeerAuthentication stays PERMISSIVE for that reason.
- NetworkPolicy (default-deny ingress) covers the three mesh namespaces,
  from `argocd-apps/components/mesh-network-policy`; k3s's kube-router
  enforces it. Allowed in: same namespace, `monitoring` and `istio-system`,
  the LAN, each node's `10.42.N.0/31` (ingress-nginx, NodePorts, promtail)
  and `169.254.7.127` (ambient kubelet probes). Symptom of a missing allow:
  ingress 502 or a connection timeout, often after adding a node (add its
  /31) or a new caller namespace. Quick test from outside the allowed set:
  `kubectl -n default run np-probe --image=busybox:1.36 --rm -i --restart=Never -- nc -z -w 5 <pod-ip> <port>`.
- Out of the mesh on purpose (`istio.io/dataplane-mode: none`):
  speedtest-exporter, blackbox-exporter-public.
- Roll a namespace back to sidecars: `kubectl label ns <ns>
  istio.io/dataplane-mode- istio-injection=enabled`, then restart its
  deployments (and set the same in k3s_apps_ambient_namespaces).
- istiod is pinned to git-k3s-server (nodeSelector) — a control-plane reboot
  restarts the whole mesh control plane. ztunnel and waypoints reconnect automatically.
- Workload cert rotation is automatic (24h lifetime); the alert fires only if
  expiry keeps dropping without renewal (stuck rotation).
- Tempo storage: if the tempo-storage PVC trends full, reduce trace volume or
  compaction retention in its manifest.
- Watchdog misses on **many pods across several nodes at the same time** mean
  the Proxmox host was CPU-starved (12 cores, ~11 vCPUs allocated), not that a
  proxy is broken. Usual cause: a CI full redeploy (see `gh run list`) or a
  backup. Check `sum(increase(envoy_server_watchdog_miss[2m]))` against host-node
  CPU. Only misses that keep growing on ONE pod are worth acting on: check that
  pod's CPU throttling (`container_cpu_cfs_throttled_periods_total{container="istio-proxy"}`)
  and restart it if the proxy is wedged. (2026-10-08: 24 misses on 15 pods
  during two back-to-back CI deploys; the threshold was raised to >10/15m for 10m.)
