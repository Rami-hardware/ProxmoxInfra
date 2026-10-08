#!/usr/bin/env bash
# alert-fixer.sh — cron entry: if Alertmanager has active alerts, let Claude Code fix them.
# Installed in crontab: * * * * * "$HOME/bin/alert-fixer.sh" >> "$HOME/.local/state/alert-fixer.log" 2>&1
# Source of truth: <repo>/scripts/alert-fixer.sh — install with `install -m 755 scripts/alert-fixer.sh ~/bin/`.
# Agent prompt: <repo>/.claude/agents/alert-fixer.md. Previous opencode version: ~/bin/alert-fixer.opencode.sh.bak
set -euo pipefail

AM_URL="http://192.168.10.203:9093"
REPO_DIR="$HOME/Desktop/new server"
CLAUDE_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null | sort -V | tail -1)"
PATH="$(dirname "${CLAUDE_BIN:-/nonexistent/x}"):$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
MODEL="opus"
MIN_AGE_SECONDS=30       # only act on alerts firing for >= 30s (skips instant flap)
COOLDOWN_SECONDS=1200    # don't re-investigate a still-firing fingerprint within 20 min
CACHE_TTL_SECONDS=21600  # forget cached alerts after 6h
CACHE_FILE="$HOME/.local/state/alert-fixer-cache.json"
TIMEOUT="30m"
TAG="[alert-fixer $(date '+%Y-%m-%d %H:%M:%S')]"

# Hard guardrails — deny rules are enforced even under bypassPermissions.
# --setting-sources project keeps user plugins/hooks (and their output styles) out of the run.
SETTINGS_JSON='{
  "permissions": {
    "deny": [
      "Bash(terraform apply:*)", "Bash(terraform destroy:*)", "Bash(terraform state:*)",
      "Bash(git push:*)", "Bash(git commit:*)", "Bash(git reset:*)", "Bash(git stash:*)",
      "Bash(git checkout:*)", "Bash(git restore:*)", "Bash(git clean:*)", "Bash(git rebase:*)",
      "Bash(crontab:*)", "Bash(rm -rf /:*)", "Bash(rm -rf ~:*)", "Bash(mkfs:*)",
      "Bash(qm destroy:*)", "Bash(qm start 100:*)",
      "Edit(**/.argocd-source-*.yaml)", "Write(**/.argocd-source-*.yaml)",
      "Edit(**/terraform.tfstate*)", "Write(**/terraform.tfstate*)",
      "Edit(.claude/**)", "Write(.claude/**)"
    ]
  }
}'

exec 9>"/tmp/alert-fixer.lock"
if ! flock -n 9; then
  echo "$TAG another run in progress (queue holds new alerts), skipping"
  exit 0
fi

if [ -z "$CLAUDE_BIN" ]; then
  echo "$TAG ERROR: claude binary not found under ~/.nvm"
  exit 1
fi

alerts="$(curl -sf -m 15 "$AM_URL/api/v2/alerts?active=true&silenced=false&inhibited=false" || true)"
if [ -z "$alerts" ] || [ "$alerts" = "null" ]; then
  echo "$TAG WARNING: could not reach Alertmanager at $AM_URL"
  exit 0
fi

now="$(date +%s)"
[ -s "$CACHE_FILE" ] && jq -e 'type == "object"' "$CACHE_FILE" >/dev/null 2>&1 || echo '{}' > "$CACHE_FILE"

# Cache schema: { fp: {alert, first_seen, last_handled, resolved} }
# Live alerts (age >= MIN_AGE) are added/refreshed; cached alerts no longer live are
# marked resolved; entries older than the TTL are dropped.
jq --argjson live "$alerts" --argjson now "$now" --argjson min_age "$MIN_AGE_SECONDS" --argjson ttl "$CACHE_TTL_SECONDS" '
  ([$live[] | select((.startsAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) <= ($now - $min_age))]
    | map({key: .fingerprint, value: .}) | from_entries) as $fresh
  | with_entries(select(.value.first_seen > ($now - $ttl)))
  | with_entries(.value.resolved = (($fresh[.key]) == null))
  | reduce ($fresh | to_entries[]) as $e (.;
      .[$e.key] = ((.[$e.key] // {first_seen: $now, last_handled: 0}) + {alert: $e.value, resolved: false}))
' "$CACHE_FILE" > "$CACHE_FILE.tmp"
mv "$CACHE_FILE.tmp" "$CACHE_FILE"

# Queue: live alerts never handled or past cooldown; resolved alerts never handled
# (post-mortem once). Resolved alerts that were already handled are not re-queued.
todo_fps="$(jq -r --argjson now "$now" --argjson cd "$COOLDOWN_SECONDS" '
  [to_entries[]
    | select(.value.last_handled == 0
             or ((.value.resolved | not) and ($now - .value.last_handled) >= $cd))
    | .key] | join(",")
' "$CACHE_FILE")"

if [ -z "$todo_fps" ]; then
  echo "$TAG nothing queued ($(jq 'length' "$CACHE_FILE") cached, all handled/cooldown)"
  exit 0
fi

payload="$(jq -c --arg fps "$todo_fps" '[
  ($fps | split(",")) as $q
  | to_entries[] | select(.key as $k | $q | index($k))
  | .value.alert + {__cache: {resolved: .value.resolved}}
]' "$CACHE_FILE")"
count="$(jq 'length' <<<"$payload")"

# Mark handled before launch so a killed run can't cause launch-per-minute spam
jq --arg fps "$todo_fps" --argjson now "$now" '
  ($fps | split(",")) as $q
  | with_entries(if (.key as $k | $q | index($k)) then .value.last_handled = $now else . end)
' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"

echo "$TAG invoking claude for $count alert(s): $todo_fps"
cd "$REPO_DIR"
rc=0
timeout --signal=INT --kill-after=60 "$TIMEOUT" "$CLAUDE_BIN" -p \
  --agent alert-fixer \
  --model "$MODEL" \
  --permission-mode bypassPermissions \
  --setting-sources project \
  --settings "$SETTINGS_JSON" \
  --strict-mcp-config \
  --name "alert-fixer: $count firing" \
  --output-format text \
  "Alertmanager alert payloads (alerts with __cache.resolved=true are no longer active - investigate post-mortem and post via /report): ${payload}
Diagnose the root cause of each, apply the fix, report to Discord, then verify against Prometheus/Alertmanager." \
  </dev/null || rc=$?
echo "$TAG done (exit $rc)"
