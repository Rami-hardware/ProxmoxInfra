#!/usr/bin/env bash
# Decide which Ansible playbooks this CI run must apply, and write
# gateway/monitoring/media/git_k3s=true|false to $GITHUB_OUTPUT.
#
# A full redeploy CPU-starves the Proxmox host (Envoy watchdog / ingress 5xx
# alerts), so a push only re-runs the playbooks whose files changed. Anything
# not clearly owned by one host runs all four — an extra deploy is cheap, a
# skipped one leaves a host out of date.
#
# The diff base is the last commit that passed the whole pipeline on this
# branch, not github.event.before: the concurrency group drops queued runs, so
# a dropped push's changes would otherwise never deploy. A failed run does not
# move the base, so the next run retries its changes.
#
# staging is a canary that deploys its own code to the hosts it changed. On
# main, files that any staging run since main's last success differs on are
# added too, so main puts its version back on hosts staging touched (a no-op
# once staging is merged; a revert if staging was abandoned).
set -euo pipefail

declare -A want=([gateway]=false [monitoring]=false [media]=false [git_k3s]=false [ci_runners]=false)

finish() {
  echo "Reason: $1"
  {
    for h in gateway monitoring media git_k3s ci_runners; do echo "$h=${want[$h]}"; done
  } >> "$GITHUB_OUTPUT"
  {
    echo "### Hosts to deploy"
    echo "$1"
    echo
    for h in gateway monitoring media git_k3s ci_runners; do echo "- \`$h\`: ${want[$h]}"; done
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

all() {
  for h in "${!want[@]}"; do want[$h]=true; done
  finish "$1"
}

[ "$GITHUB_EVENT_NAME" = push ] || all "$GITHUB_EVENT_NAME run deploys every host"

runs_api="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/workflows/main.yml/runs"
api() { curl -fsSG -H "Authorization: Bearer $GH_TOKEN" "$runs_api" "$@"; }

read -r base base_time < <(api --data-urlencode "branch=$GITHUB_REF_NAME" \
  --data-urlencode status=success --data-urlencode per_page=1 \
  | jq -r '.workflow_runs[0] | "\(.head_sha // "") \(.created_at // "")"') || base=""

[ -n "$base" ] || all "no previous successful run found on $GITHUB_REF_NAME"
git cat-file -e "$base^{commit}" 2>/dev/null || all "last deployed commit $base is not in the clone"
git merge-base --is-ancestor "$base" "$GITHUB_SHA" || all "last deployed commit $base is not an ancestor (force push?)"

echo "Changes since last successful run ($base):"
changed=$(git diff --name-only "$base" "$GITHUB_SHA")
echo "$changed"

if [ "$GITHUB_REF_NAME" = main ]; then
  # Any completed run counts: a failed staging deploy may still have changed hosts.
  staging_shas=$(api --data-urlencode branch=staging --data-urlencode status=completed \
    --data-urlencode "created=>=$base_time" --data-urlencode per_page=100 \
    | jq -r '.workflow_runs[].head_sha' | sort -u) \
    || all "could not list staging runs since $base_time"
  for s in $staging_shas; do
    git cat-file -e "$s^{commit}" 2>/dev/null || all "staging commit $s is not in the clone"
    staged=$(git diff --name-only "$base" "$s")
    echo "Files staging run $s may have deployed (vs $base):"
    echo "$staged"
    changed+=$'\n'"$staged"
  done
fi

# Role lists mirror the playbooks. A role missing here falls through to the
# Ansbile/* catch-all and deploys every host, so forgetting to update this is
# safe, just slower. `common` is in every playbook, hence the catch-all.
while IFS= read -r f; do
  case "$f" in
    '') ;;
    Ansbile/argocd-apps/*) ;;  # ArgoCD syncs these itself
    Ansbile/gateway-server.yml | Ansbile/group_vars/gateway-vm.yml | \
    Ansbile/roles/adguard/* | Ansbile/roles/nginx_config/* | Ansbile/roles/ufw/*)
      want[gateway]=true ;;
    Ansbile/monitoring-server.yml | Ansbile/group_vars/monitoring-vm.yml | \
    Ansbile/roles/unbound/* | Ansbile/roles/prometheus/* | Ansbile/roles/loki/* | \
    Ansbile/roles/alertmanager/* | Ansbile/roles/grafana/*)
      want[monitoring]=true ;;
    Ansbile/media-server.yml | Ansbile/group_vars/media-vm.yml | \
    Ansbile/roles/intel_arc/* | Ansbile/roles/scraparr/*)
      want[media]=true ;;
    # Shared by the k3s server (hand-installed runner) and the runner LXCs.
    Ansbile/roles/docker_setup/* | Ansbile/roles/ci_runner/*)
      want[git_k3s]=true; want[ci_runners]=true ;;
    # Ansbile/apps/ is the alert-forwarder image, which k3s_apps deploys.
    Ansbile/git-k3s-server.yml | Ansbile/group_vars/git-k3s-server-vm.yml | \
    Ansbile/roles/dns/* | Ansbile/roles/k3s_server/* | Ansbile/roles/k3s_apps/* | Ansbile/apps/*)
      want[git_k3s]=true ;;
    Ansbile/ci-runners.yml | Ansbile/group_vars/ci-runner-lxc.yml)
      want[ci_runners]=true ;;
    # Shared Ansible files (common role, group_vars/all, inventory, collections)
    # and the pipeline itself.
    Ansbile/* | .github/*)
      all "shared file changed: $f" ;;
    *) ;;  # Terraform (planned every run), docs, tools: no playbook
  esac
done <<< "$changed"

finish "only playbooks whose files changed since $base"
