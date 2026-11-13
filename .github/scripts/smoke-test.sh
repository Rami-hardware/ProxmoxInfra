#!/usr/bin/env bash
# Post-deploy smoke test: does the lab actually work after this deploy?
#   smoke-test.sh <host>...   (deploy.yml host keys that deployed:
#                              gateway monitoring media git_k3s ci_runners host_node)
# Cluster-wide checks always run (every host change can break the cluster's
# routing or DNS); the Prometheus target check covers only the given hosts.
# Pods restart after a deploy, so failing checks are retried for up to
# SMOKE_TIMEOUT seconds before the test fails. On staging this is the canary
# verdict; promote.yml only promotes a green staging run, so a failed smoke
# test also blocks the promote.
set -uo pipefail

PROM=${PROMETHEUS_URL:-http://192.168.10.203:9090}
AM=${ALERTMANAGER_URL:-http://192.168.10.203:9093}
LOKI=${LOKI_URL:-http://192.168.10.203:3100}
DNS_SERVERS=${DNS_SERVERS:-"192.168.10.200 192.168.10.203"}
INGRESS_IP=${INGRESS_IP:-192.168.10.210}
TIMEOUT=${SMOKE_TIMEOUT:-120}
exec 3>&1  # warnings from inside a check's $( ) still reach the log

# deploy.yml host key → Prometheus `instance` label.
declare -A instance=([gateway]=gateway-server [monitoring]=monitoring-server [media]=media-server
                     [git_k3s]=git-k3s-server [host_node]=host-node [ci_runners]='ci-runner-.*')
instances=$(for h in "$@"; do [ -n "${instance[$h]:-}" ] && echo "${instance[$h]}"; done | paste -sd'|' -)

# Each check prints why it failed on stdout and returns non-zero.

check_nodes() {
  kubectl get nodes --no-headers | awk '$2 != "Ready" {print "node " $1 " is " $2; bad=1} END {exit bad}'
}

check_workloads() {
  # Deployments/DaemonSets/StatefulSets with fewer ready replicas than wanted,
  # and pods stuck in a crash/pull loop.
  kubectl get deploy,ds,sts -A -o json | jq -r '.items[]
    | select((.status.readyReplicas // .status.numberReady // 0) < (.spec.replicas // .status.desiredNumberScheduled // 0))
    | "\(.kind) \(.metadata.namespace)/\(.metadata.name) not ready"' | grep . && return 1
  kubectl get pods -A -o json | jq -r '.items[] | .metadata as $m
    | (.status.containerStatuses // [])[] | select(.state.waiting.reason // "" | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError"))
    | "pod \($m.namespace)/\($m.name): \(.state.waiting.reason)"' | grep . && return 1
  return 0
}

check_argocd() {
  # Health must be Healthy. OutOfSync is only reported: ArgoCD polls git, so
  # a fresh app push is OutOfSync for a few minutes by design.
  local apps
  apps=$(kubectl -n argocd get applications -o json)
  jq -r '.items[] | select(.status.sync.status != "Synced") | "::warning::ArgoCD app \(.metadata.name) is \(.status.sync.status)"' <<< "$apps" >&3
  jq -r '.items[] | select(.status.health.status != "Healthy") | "ArgoCD app \(.metadata.name) is \(.status.health.status)"' <<< "$apps" | grep . && return 1
  return 0
}

check_ingress() {
  # Every Ingress host, straight at ingress-nginx. 5xx or no answer = down;
  # anything else (200, a login redirect, Tempo's 404 on /) means the route
  # and the backend answer.
  local h code bad=0
  for h in $(kubectl get ingress -A -o jsonpath='{.items[*].spec.rules[*].host}' | tr ' ' '\n' | sort -u); do
    code=$(curl -sk -o /dev/null --max-time 10 --resolve "$h:443:$INGRESS_IP" -w '%{http_code}' "https://$h/")
    if [ "$code" = 000 ] || [ "$code" -ge 500 ]; then echo "https://$h/ → $code"; bad=1; fi
  done
  return $bad
}

check_dns() {
  local s ip bad=0
  for s in $DNS_SERVERS; do
    ip=$(dig +short +time=3 +tries=1 @"$s" grafana.homelab.lan | tail -1)
    [ "$ip" = "$INGRESS_IP" ] || { echo "DNS $s: grafana.homelab.lan → '${ip:-no answer}'"; bad=1; }
    [ -n "$(dig +short +time=3 +tries=1 @"$s" github.com)" ] || { echo "DNS $s: github.com does not resolve"; bad=1; }
  done
  return $bad
}

check_monitoring() {
  local bad=0
  curl -sf --max-time 5 -o /dev/null "$PROM/-/ready" || { echo "Prometheus not ready"; bad=1; }
  curl -sf --max-time 5 -o /dev/null "$AM/-/ready" || { echo "Alertmanager not ready"; bad=1; }
  # Loki's /ready reports "Ingester not ready" while it serves fine, so ask
  # the query API instead.
  curl -sf --max-time 5 -o /dev/null "$LOKI/loki/api/v1/labels" || { echo "Loki query API not answering"; bad=1; }
  return $bad
}

check_targets() {
  # Scrape targets of the deployed hosts that are down.
  [ -n "$instances" ] || return 0
  curl -sf --max-time 5 "$PROM/api/v1/query" --data-urlencode "query=up{instance=~\"$instances\"} == 0" \
    | jq -r '.data.result[] | "target down: \(.metric.job) on \(.metric.instance)"' | grep . && return 1
  return 0
}

checks=(nodes workloads argocd ingress dns monitoring targets)
declare -A result=()
deadline=$((SECONDS + TIMEOUT))
pending=("${checks[@]}")
while :; do
  still=()
  for c in "${pending[@]}"; do
    if out=$("check_$c" 2>&1); then result[$c]=ok; else result[$c]=$out; still+=("$c"); fi
  done
  pending=("${still[@]}")
  [ "${#pending[@]}" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ] && break
  echo "Waiting on: ${pending[*]} (retry in 5s)"
  sleep 5
done

{
  echo "### Smoke test (${*:-no hosts})"
  for c in "${checks[@]}"; do
    if [ "${result[$c]}" = ok ]; then echo "- ✅ $c"
    else echo "- ❌ $c"; sed 's/^/  - /' <<< "${result[$c]}"; fi
  done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "${#pending[@]}" -gt 0 ]; then
  echo "::error::Smoke test failed after ${TIMEOUT}s: ${pending[*]}"
  exit 1
fi
echo "Smoke test passed in ${SECONDS}s."
