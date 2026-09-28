# Kubernetes workloads — deployments / pods / PVC / jobs

Covers: KubeDeploymentHasUnavailableReplicas, KubeDeploymentSpecVsAvailableReplicaMismatch,
KubePodCrashLooping, KubePodStuckInWaiting, KubePodInFailedPhase, KubeNodeNotReady,
KubePVCNotBound, KubeJobFailed, KubeCronJobStale, KubePodOOMKilled,
ContainerNearMemoryLimit, KubePVCAlmostFull, KubePVCFillForecast7d, KubeletDown

## Diagnosis
```bash
sudo k3s kubectl get pods -n <ns> -o wide
sudo k3s kubectl describe pod -n <ns> <pod>      # events at the bottom
sudo k3s kubectl logs -n <ns> <pod> --previous   # why it crashed last time
sudo k3s kubectl top pod -n <ns>                 # real usage vs limits
sudo k3s kubectl describe pvc -n <ns> <pvc>
```

## Common fixes
- CrashLoop: read `--previous` logs; usually a bad env/config or OOM
  (check `last state: terminated, reason: OOMKilled`).
- ImagePullBackOff: image tag/digest wrong or registry unreachable.
- PVC full: clean data inside the app, or grow the PV (local-path supports
  expansion; hostPath PVs must be resized on the VM by hand).
- Node NotReady: `sudo systemctl status k3s-agent` (workers) or k3s
  (control plane) on that VM; check network to 192.168.10.204.

## Note
After any node reboot expect ~2-3 min of churn (pods restart, metrics-server
and calico settle). Alerts that survive 10+ minutes are real.
