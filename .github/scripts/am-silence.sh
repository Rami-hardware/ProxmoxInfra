#!/usr/bin/env bash
# Silence warning alerts in Alertmanager while a deploy job runs.
#   am-silence.sh create <what> [<matchers>...]  → id=<ids> to $GITHUB_OUTPUT
#   am-silence.sh delete <ids>
# Each <matchers> argument is one silence: comma-separated name=value or
# name=~regex, ANDed with severity=warning. Several arguments = several
# silences (Alertmanager has no OR inside one silence). No <matchers> = every
# warning in the lab (git-k3s and tf_apply: they can touch everything).
# Each deploy job holds its own silences, so the rest of the lab still pages
# while one host deploys, and a job that ends early lifts only its own.
# Criticals always page. A silence left behind (runner lost) expires after
# 45 minutes.
set -euo pipefail

matchers_json() {
  # "a=b,c=~d" → [{name:a,value:b,isRegex:false}, {name:c,value:d,isRegex:true}]
  local m out='[{"name":"severity","value":"warning","isRegex":false,"isEqual":true}]' name value regex
  IFS=',' read -ra parts <<< "$1"
  for m in "${parts[@]}"; do
    [ -n "$m" ] || continue
    if [[ $m == *=~* ]]; then name=${m%%=~*}; value=${m#*=~}; regex=true
    else name=${m%%=*}; value=${m#*=}; regex=false; fi
    out=$(jq -c --arg n "$name" --arg v "$value" --argjson r "$regex" \
      '. + [{name: $n, value: $v, isRegex: $r, isEqual: true}]' <<< "$out")
  done
  echo "$out"
}

case "$1" in
  create)
    what=$2; shift 2
    [ $# -gt 0 ] || set -- ""
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    end=$(date -u -d '+45 minutes' +%Y-%m-%dT%H:%M:%SZ)
    ids=""
    for set in "$@"; do
      body=$(jq -n --argjson m "$(matchers_json "$set")" --arg now "$now" --arg end "$end" \
        --arg c "CI deploy $GITHUB_RUN_ID $what" \
        '{matchers: $m, startsAt: $now, endsAt: $end, createdBy: "github-actions", comment: $c}')
      id=$(curl -sf --max-time 10 -X POST "$ALERTMANAGER_URL/api/v2/silences" \
        -H 'Content-Type: application/json' -d "$body" | jq -r .silenceID)
      ids="$ids $id"
      echo "Silenced warnings${set:+ where $set} until $end (silence $id)"
    done
    echo "id=${ids# }" >> "$GITHUB_OUTPUT" ;;
  delete)
    shift
    for id in $*; do
      curl -sf --max-time 10 -X DELETE "$ALERTMANAGER_URL/api/v2/silence/$id"
      echo "Removed silence $id"
    done ;;
  *) echo "usage: $0 create <what> [<matchers>...] | delete <ids>" >&2; exit 2 ;;
esac
