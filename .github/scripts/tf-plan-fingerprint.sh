#!/usr/bin/env bash
# Prints a hash of what a saved Terraform plan would change (address, action,
# planned values). deploy.yml compares the plan shown before the Production
# approval with the one it re-plans right before applying, and refuses to
# apply if they differ — you only ever approve what you saw.
# Usage (from the Terraform root): tf-plan-fingerprint.sh tfplan
set -euo pipefail
terraform show -json "$1" \
  | jq -S -c '[.resource_changes[]? | select(.change.actions != ["no-op"])
               | {address, actions: .change.actions, after: .change.after}]' \
  | sha256sum | cut -d' ' -f1
