# SLO burn alerts — what they mean and what to do

SLOs (14-day window): local sites 99.5%, public sites 99.5%, DNS 99.9%.

## Burn-rate pattern
- **Fast burn (14.4x over 1h AND 5m)** -> something is properly down NOW.
  Treat like its underlying outage alert; the SLO alert is the
  "this is costing us real availability" framing.
- **Slow burn (6x over 6h AND 30m)** -> sustained partial flapping. Look for
  a recurring blip: rollout windows, one flapping target, or WAN instability.

## First response
```bash
curl -sk --max-time 10 'https://prometheus.homelab.lan/api/v1/query' \
  --data-urlencode 'query=slo:availability:1h' | jq .
```
Compare scopes: one scope burning = that layer; all scopes burning = shared
infrastructure (gateway/ingress/host).

## Error budget
`slo:error_budget_remaining` per scope: 1.0 = untouched, 0 = spent, negative =
over budget (freeze risky changes; fix reliability first). Budget resets on a
rolling 14d window as old failures age out.
