#!/usr/bin/env bash
set -euo pipefail
# Changes the CURRENT kubectl context. Confirm it points at the intended demo cluster.
kubectl config current-context
read -r -p 'Restart catalog/orders in namespace retail in this context? Type yes: ' answer
[[ "$answer" == "yes" ]] || exit 1
kubectl -n retail rollout restart deployment/catalog deployment/orders
kubectl -n retail rollout status deployment/catalog --timeout=300s
kubectl -n retail rollout status deployment/orders --timeout=300s
