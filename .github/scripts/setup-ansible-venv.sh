#!/usr/bin/env bash
# Builds (or reuses) the virtualenv with the pinned CI tools and prints its
# bin directory on stdout. Shared by the setup-ansible-venv action (each job)
# and roles/ci_runner (pre-warms new runners so their first job is fast).
# The venv lives in ~/.cache, keyed by the requirements file's hash.
# Usage: setup-ansible-venv.sh <ci-requirements.txt>
set -euo pipefail
req=$1
root="$HOME/.cache/ci-ansible-venv"
venv="$root/$(sha256sum "$req" | cut -c1-12)"
# ansible-lint is installed last, so its presence means a finished venv.
if [ ! -x "$venv/bin/ansible-lint" ]; then
  echo "Building $venv" >&2
  rm -rf "$root"  # drop venvs for older pins — small runner disk
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet -r "$req" >&2
else
  echo "Reusing $venv" >&2
fi
echo "$venv/bin"
