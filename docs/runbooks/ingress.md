# Ingress — ingress-nginx alerts

Covers: IngressControllerDown, IngressConfigReloadFailed, IngressSSLCertificateExpiringSoon,
IngressOrphanedIngress, IngressHigh5xxRateFromUpstreams, IngressConnectionCountNearWorkerLimit,
IngressAdmissionWebhookFailures

## Diagnosis
```bash
sudo k3s kubectl get pods -n ingress-nginx
sudo k3s kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=50
sudo k3s kubectl get ing -A                            # what's routed where
curl -sk -o /dev/null -w '%{http_code}
' https://<site>
```

## Notes
- Controller runs on git-k3s-server with MetalLB announcing 192.168.10.210
  (layer2). A git-k3s reboot = brief ingress outage + a burst of probe alerts.
- Config reload failed = an ingress with a bad annotation/config is blocking
  EVERY new route from going live. Find the offending ingress in controller
  logs and fix or delete it.
- High 5xx with healthy pods = upstream app errors; follow the app's logs.
