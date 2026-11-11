#!/usr/bin/env bash
# failover-drill.sh — game day for the ingress: rolling-restart ingress-nginx
# (which moves the MetalLB IP between nodes) while probing one site on the LAN
# and through Cloudflare twice a second. Prints the error count per path and
# every node the LoadBalancer IP was announced from.
#
# Run from a LAN machine with `ssh git` access:   scripts/failover-drill.sh
# Expected result (2026-11-11): 0 errors on both paths. Before the
# shutdown-grace fix it was ~25s of errors per IP move (Cloudflare 521).
# Results go in docs/runbooks/ingress.md.
set -euo pipefail

HOST="${HOST:-jellyfin.darkestserver.com}"
URL_PATH="${URL_PATH:-/web/}"
LB_IP="${LB_IP:-192.168.10.210}"
DURATION="${DURATION:-420}"   # seconds; a rollout waits up to 300s for open streams

kubectl() { ssh git sudo -n k3s kubectl "$@"; }

public_ip=$(dig +short "$HOST" @1.1.1.1 | grep -E '^[0-9.]+$' | head -1)
[ -n "$public_ip" ] || { echo "no public IP for $HOST"; exit 1; }
log=$(mktemp)
trap 'rm -f "$log"' EXIT

probe() {  # $1 = IP to connect to
  curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    --resolve "$HOST:443:$1" "https://$HOST$URL_PATH" || true
}

echo "Probing $HOST for ${DURATION}s (LAN via $LB_IP, public via Cloudflare $public_ip)"
end=$((SECONDS + DURATION))
(
  while [ $SECONDS -lt $end ]; do
    echo "$(date +%T) lan=$(probe "$LB_IP") public=$(probe "$public_ip")"
    sleep 0.5
  done
) > "$log" &
prober=$!

(
  last=""
  while [ $SECONDS -lt $end ]; do
    node=$(kubectl get servicel2statuses -A -o jsonpath='{.items[0].status.node}' 2>/dev/null || true)
    [ "$node" != "$last" ] && echo "$(date +%T) LoadBalancer IP announced from: ${node:-<none>}"
    last=$node
    sleep 2
  done
) &
watcher=$!

sleep 10
echo "$(date +%T) rolling restart of ingress-nginx"
kubectl -n ingress-nginx rollout restart deploy/ingress-nginx-controller
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout="${DURATION}s"
wait "$prober" "$watcher"

total=$(wc -l < "$log")
lan_err=$(grep -vc 'lan=200' "$log" || true)
pub_err=$(grep -Evc 'public=(200|301|302)' "$log" || true)
echo
echo "Samples: $total   LAN errors: $lan_err   public errors: $pub_err"
grep -Ev 'lan=200 public=(200|301|302)' "$log" | sed -n '1,10p'
[ "$lan_err" = 0 ] && [ "$pub_err" = 0 ]
