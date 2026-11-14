#!/usr/bin/env bash
# Decide which playbooks — and which roles inside them — this CI run must
# apply. Writes <host>=true|false and <host>_tags=<comma list> to
# $GITHUB_OUTPUT; an empty <host>_tags means the whole playbook.
#
# A changed file under roles/<r>/ runs only role r (ansible-playbook --tags r;
# every playbook tags each role with its own name) on every host whose
# playbook lists it — read from the playbooks, so there is no list to keep in
# sync. A host's playbook or group_vars runs that whole host. Anything not
# clearly owned by a role or host runs everything: an extra deploy is cheap, a
# skipped one leaves a host out of date.
#
# Also writes lint_paths (the roles/playbooks/vars files ansible-lint checks:
# only what changed, or Ansbile/ when everything runs) and syntax_playbooks
# (the playbooks of the hosts that deploy).
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

# Playbooks per host, plus the two Terraform roots (only planned when touched).
# terraform_apply is stricter than terraform: it is true only when this deploy
# contains a Proxmox Terraform code change (.tf/.tfvars). Drift, scheduled and
# full runs, and state-only commits plan and report, but never apply.
declare -A want=([gateway]=false [monitoring]=false [media]=false [git_k3s]=false [ci_runners]=false [host_node]=false [terraform]=false [terraform_apply]=false [cloudflare]=false)

hosts=(gateway monitoring media git_k3s ci_runners host_node)
# Playbook and group_vars file per host.
declare -A playbook=([gateway]=gateway-server [monitoring]=monitoring-server [media]=media-server
                     [git_k3s]=git-k3s-server [ci_runners]=ci-runners [host_node]=host-node)
declare -A hostvars_file=([gateway]=gateway-vm [monitoring]=monitoring-vm [media]=media-vm
                          [git_k3s]=git-k3s-server-vm [ci_runners]=ci-runner-lxc [host_node]=host-node)
# Roles to run per host: ALL = the whole playbook, else a space list.
declare -A tags=()
# Ansible paths ansible-lint checks (keys; ALL = the whole Ansbile/ tree).
declare -A lint=()

# Comma list for --tags, or empty for the whole playbook.
tag_list() {
  [ "${tags[$1]:-}" = ALL ] && return
  tr ' ' '\n' <<< "${tags[$1]:-}" | sed '/^$/d' | sort -u | paste -sd, -
}

finish() {
  echo "Reason: $1"
  local lint_paths="" syntax=""
  if [ -n "${lint[ALL]:-}" ]; then lint_paths=Ansbile/
  else
    # Existing paths only: a deleted role or playbook has nothing to lint.
    for p in "${!lint[@]}"; do [ -e "$p" ] && lint_paths="$lint_paths $p"; done
    lint_paths=$(tr ' ' '\n' <<< "$lint_paths" | sed '/^$/d' | sort | paste -sd' ' -)
  fi
  for h in "${hosts[@]}"; do ${want[$h]} && syntax="$syntax Ansbile/${playbook[$h]}.yml"; done
  {
    for h in "${hosts[@]}"; do echo "$h=${want[$h]}"; echo "${h}_tags=$(tag_list "$h")"; done
    for h in terraform terraform_apply cloudflare; do echo "$h=${want[$h]}"; done
    echo "lint_paths=$lint_paths"
    echo "syntax_playbooks=${syntax# }"
  } >> "$GITHUB_OUTPUT"
  {
    echo "### Deploy targets"
    echo "$1"
    echo
    for h in "${hosts[@]}"; do
      if ! ${want[$h]}; then echo "- \`$h\`: —"
      elif [ -z "$(tag_list "$h")" ]; then echo "- \`$h\`: **whole playbook**"
      else echo "- \`$h\`: roles \`$(tag_list "$h")\`"; fi
    done
    for h in terraform terraform_apply cloudflare; do echo "- \`$h\`: ${want[$h]}"; done
    echo "- ansible-lint: \`${lint_paths:-—}\`"
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

all() {
  # Everything is planned and deployed. terraform_apply keeps its own value:
  # "deploy everything" is not a Terraform code change, but a shared-file
  # change in the same diff must not hide one (set below, before the loop).
  for h in "${!want[@]}"; do [ "$h" = terraform_apply ] || want[$h]=true; done
  for h in "${hosts[@]}"; do tags[$h]=ALL; done
  lint[ALL]=1
  finish "$1"
}

# Schedule and a plain manual run deploy everything; promote.yml dispatches
# with full_deploy=false to get the same selective deploy as a push.
[ "$GITHUB_EVENT_NAME" = push ] || [ "${FULL_DEPLOY:-true}" = false ] \
  || all "$GITHUB_EVENT_NAME run deploys every host"

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

# Decided over the whole diff first: the loop below may stop early at a
# shared file (all) before it reaches the Terraform paths.
grep -qE '^Terraform/([^/]+\.(tf|tfvars)|modules/.+)$' <<< "$changed" && want[terraform_apply]=true

# Roles a host's playbook runs (each listed as `- { role: x, tags: [x] }`).
roles_of() { sed -nE 's/^[[:space:]]*- \{ role: ([a-z0-9_]+),.*/\1/p' "Ansbile/${playbook[$1]}.yml"; }

host_all() { want[$1]=true; tags[$1]=ALL; }

# Run role $1 (or only its tags $2..., default: the whole role) on every
# host whose playbook has it.
run_role() {
  local role=$1 found=false h; shift
  local want_tags=${*:-$role}
  lint[Ansbile/roles/$role]=1
  for h in "${hosts[@]}"; do
    roles_of "$h" | grep -qx "$role" || continue
    found=true; want[$h]=true
    [ "${tags[$h]:-}" = ALL ] || tags[$h]="${tags[$h]:-} $want_tags"
  done
  $found || all "role $role is in no playbook (a dependency?)"
}

# A role may split its tasks into tasks/<part>.yml, imported in main.yml with
# `tags: [<role>_<part>]` (k3s_apps does). Print the tags that cover changed
# file $2 of role $1: its own part for tasks/<part>.yml, or every part that
# references a template/file by name. Prints the role name (= whole role) for
# main.yml, defaults, handlers, or anything it can't pin to a part.
role_parts() {
  local role=$1 rel=$2 dir="Ansbile/roles/$1" part out="" f
  part_tag() { grep -qE "^[[:space:]]*tags: \[${role}_$1\]" "$dir/tasks/main.yml" 2>/dev/null && echo "${role}_$1"; }
  case "$rel" in
    tasks/main.yml) ;;
    tasks/*.yml)
      part=${rel#tasks/}; out=$(part_tag "${part%.yml}") ;;
    templates/* | files/*)
      for f in $(grep -lF "$(basename "$rel")" "$dir"/tasks/*.yml 2>/dev/null); do
        part=$(basename "$f" .yml)
        [ "$part" = main ] && { out=""; break; }
        t=$(part_tag "$part") || { out=""; break; }
        out="$out $t"
      done ;;
  esac
  echo "${out:-$role}"
}

while IFS= read -r f; do
  case "$f" in
    '') ;;
    # The Application CRs themselves (Image Updater annotations, source path)
    # are applied by k3s_apps, not synced by ArgoCD.
    Ansbile/argocd-apps/*-app.yaml) run_role k3s_apps k3s_apps_image_updater ;;
    Ansbile/argocd-apps/*) ;;  # ArgoCD syncs these itself
    Ansbile/roles/*/*)
      r=${f#Ansbile/roles/}
      # shellcheck disable=SC2046  # word-split the tag list on purpose
      run_role "${r%%/*}" $(role_parts "${r%%/*}" "${r#*/}") ;;
    # The alert-forwarder image + chart, which k3s_apps deploys.
    Ansbile/apps/*) run_role k3s_apps k3s_apps_alert_forwarder ;;
    # Only adguard and unbound read the local DNS names.
    Ansbile/group_vars/all/local_dns.yml) lint[$f]=1; run_role adguard; run_role unbound ;;
    Ansbile/*.yml | Ansbile/group_vars/*.yml)
      matched=false
      for h in "${hosts[@]}"; do
        if [ "$f" = "Ansbile/${playbook[$h]}.yml" ] || [ "$f" = "Ansbile/group_vars/${hostvars_file[$h]}.yml" ]; then
          host_all "$h"; matched=true; lint[$f]=1
        fi
      done
      $matched || all "shared file changed: $f" ;;
    # Shared Ansible files (vault, inventory, collections) and the pipeline.
    Ansbile/* | .github/*)
      all "shared file changed: $f" ;;
    Terraform/cloudflare/*) want[cloudflare]=true ;;
    Terraform/*) want[terraform]=true ;;
    *) ;;  # docs, tools: nothing to deploy
  esac
done <<< "$changed"

finish "only roles/playbooks whose files changed since $base"
