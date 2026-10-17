#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${TERRAFORM_BIN:-terraform}"
"$TF" -chdir="$ROOT" fmt -check -recursive
for stage in 01-infra 02-platform 03-apps; do
  "$TF" -chdir="$ROOT/$stage" init -backend=false -input=false
  "$TF" -chdir="$ROOT/$stage" validate
 done
# No plan, apply, AWS API calls or Kubernetes writes are performed by this script.
