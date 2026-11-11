# Ingress — ingress-nginx alerts

Covers: IngressControllerDown, IngressConfigReloadFailed, IngressSSLCertificateExpiringSoon,
IngressOrphanedIngress, IngressHigh5xxRateFromUpstreams, IngressConnectionCountNearWorkerLimit,
IngressAdmissionWebhookFailures, IngressAppLatencyHigh

## Diagnosis
```bash
sudo k3s kubectl get pods -n ingress-nginx
sudo k3s kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=50
sudo k3s kubectl get ing -A                            # what's routed where
curl -sk -o /dev/null -w '%{http_code}
' https://<site>
```

## Notes
- Two controller replicas (hostNetwork), one each on git-k3s-server and
  monitoring-server (`k3s_apps_ingress_nodes`). MetalLB announces
  192.168.10.210 (layer2) from one node with a Ready pod; if that node dies the
  IP moves to the other within a few seconds. A stopping controller keeps
  serving for 15s (`shutdown-grace-period`) while its readiness fails (2s x 2),
  so MetalLB moves the IP before nginx closes. Measured before that fix: ~25s
  of LAN and public (Cloudflare 521) errors per move.
- Game day: `scripts/failover-drill.sh` (rolling restart while probing LAN
  and Cloudflare). 2026-11-12: 327 samples, 0 LAN and 0 public errors, IP
  moved git -> monitoring -> git. Re-run after any ingress or MetalLB change. IngressControllerDown fires per
  node, so one alert = degraded, not down.
- See which node holds the IP:
  `sudo k3s kubectl get servicel2statuses -A -o custom-columns=SVC:.status.serviceName,NODE:.status.node`
- Restart with no downtime: `sudo k3s kubectl -n ingress-nginx rollout restart deploy/ingress-nginx-controller`
  (one pod at a time).
- Config reload failed = an ingress with a bad annotation/config is blocking
  EVERY new route from going live. Find the offending ingress in controller
  logs and fix or delete it.
- High 5xx with healthy pods = upstream app errors; follow the app's logs.
- IngressAppLatencyHigh: open Grafana -> "Request path latency" and compare
  the panels for that host. *App time* ~= *Total time* means the app is slow
  (ingress adds ~0); check its pod CPU/memory and logs. A high *Network hop*
  (upstream connect) means the node or pod network: check the node and
  flannel. Seerr is the known slow one (p95 ~2s): its discover, movie and
  tv pages call the TMDB API live, several calls per page at ~160-300ms
  each (measured 2026-11-11); local endpoints like /api/v1/request/count
  answer in ~0.1s. Not a network or ingress problem.
