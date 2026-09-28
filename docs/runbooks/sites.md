# Sites & SLO burn — HTTP probe alerts

Covers: LocalServiceDown, PublicSiteDown, SiteHTTPStatusError,
SiteRespondingSlowly, ExcessiveRedirects, CertExpiringSoon,
SpeedtestExporterDown, BlackboxExporterDown, SLOLocalSitesFastBurn,
SLOLocalSitesSlowBurn, SLOPublicSitesFastBurn, SLOPublicSitesSlowBurn

## Diagnosis
```bash
curl -sk -o /dev/null -w '%{http_code} %{time_total}s
' https://<site>
sudo k3s kubectl get pods -n <ns>            # is the app up?
sudo k3s kubectl get pods -n ingress-nginx   # is ingress up?
curl -sk https://<site> -v 2>&1 | grep -E 'SSL|HTTP'   # TLS details
```

## Decision tree
1. blackbox-exporter itself down (`BlackboxExporterDown`) -> fix that first;
   all other probe alerts are blind.
2. One site down, pod running -> ingress path: check ingress-nginx logs and
   the service endpoints (`kubectl get endpoints -n <ns> <svc>`).
3. Everything down at once -> ingress-nginx, MetalLB announcement, or gateway.
4. 5xx but pod healthy -> app erroring; check its logs
   (`kubectl logs -n <ns> deploy/<app> --tail=50`).
5. SLO burn alerts -> see slo.md; usually a shared cause, not per-site fixes.

## Rollout false positives
Image Updater bumps restart pods; probe failures during rollouts self-resolve.
If alerts fire only right after a deploy, wait one refresh cycle before diving in.
