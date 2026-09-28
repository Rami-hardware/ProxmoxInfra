# DNS — AdGuard / CoreDNS alerts

Covers: AdGuardDNSDown, AdGuardProtectionDisabled, AdGuardQueriesStopped,
AdGuardExporterDown, CoreDNSDown, CoreDNSForwardHealthBroken, CoreDNSPanics,
CoreDNSReloadFailures, CoreDNSForwardMaxConcurrentRejects, CoreDNSHighRequestLatency,
CoreDNSCacheHitRatioDropping, CoreDNSKubernetesAPIClientErrors, CoreDNSDNSResponseErrors,
SlowDNSResolution

## The DNS chain
pods -> CoreDNS (k3s) -> AdGuard Home (gateway, 192.168.10.200:53) -> upstream

## Diagnosis
```bash
nslookup google.com 192.168.10.200          # AdGuard answering?
nslookup google.com 192.168.10.203          # CoreDNS (node IP) answering?
ssh gateway@192.168.10.200 'systemctl status adguard'
sudo journalctl -u adguard -n 30
sudo k3s kubectl logs -n kube-system -l k8s-app=kube-dns --tail=30
```

## Common fixes
- AdGuard down: `sudo systemctl restart adguard` on the gateway. Expect
  CoreDNSForwardHealthBroken + SLO DNS burn alerts to fire and self-resolve.
- Protection disabled: re-enable filtering in the AdGuard UI — the network is
  unfiltered until you do.
- CoreDNS config change gone wrong: the Corefile comes from the k3s manifest
  (`/var/lib/rancher/k3s/server/manifests/coredns.yaml`).

## Note
The whole cluster resolves through this chain — a total DNS failure also
fires LocalServiceDown (every site), SLO burn alerts, and pod DNS errors.
