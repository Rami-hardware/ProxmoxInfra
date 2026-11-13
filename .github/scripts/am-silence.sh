#!/usr/bin/env bash
# Silence warning alerts in Alertmanager while a deploy job runs.
#   am-silence.sh create <what>   → prints id=<silence id> to $GITHUB_OUTPUT
#   am-silence.sh delete <id>
# Each deploy job (host jobs, tf_apply) holds its own silence, so a job that
# ends early lifts only its own; the others stay covered. Deploys restart pods
# and briefly fail probes, which used to page as warnings. Criticals still
# page. A silence left behind (runner lost) expires after 45 minutes.
set -euo pipefail

case "$1" in
  create)
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    end=$(date -u -d '+45 minutes' +%Y-%m-%dT%H:%M:%SZ)
    body=$(jq -n --arg now "$now" --arg end "$end" --arg c "CI deploy $GITHUB_RUN_ID $2" \
      '{matchers: [{name: "severity", value: "warning", isRegex: false, isEqual: true}],
        startsAt: $now, endsAt: $end, createdBy: "github-actions", comment: $c}')
    id=$(curl -sf --max-time 10 -X POST "$ALERTMANAGER_URL/api/v2/silences" \
      -H 'Content-Type: application/json' -d "$body" | jq -r .silenceID)
    echo "id=$id" >> "$GITHUB_OUTPUT"
    echo "Silenced warnings until $end (silence $id)" ;;
  delete)
    curl -sf --max-time 10 -X DELETE "$ALERTMANAGER_URL/api/v2/silence/$2"
    echo "Removed silence $2" ;;
  *) echo "usage: $0 create <what> | delete <id>" >&2; exit 2 ;;
esac
