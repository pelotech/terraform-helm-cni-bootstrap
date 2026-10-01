#!/usr/bin/env bash
# Poll until COUNT nodes match SELECTOR, using a temporary kubeconfig so the caller's is untouched.
set -euo pipefail

export KUBECONFIG
KUBECONFIG="$(mktemp)"
trap 'rm -f "$KUBECONFIG"' EXIT
if [ -n "${KUBECONFIG_CONTENT:-}" ]; then
  printf '%s\n' "$KUBECONFIG_CONTENT" > "$KUBECONFIG"
else
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null
fi

label_desc="${SELECTOR:-<any>}"
while :; do
  # An unreachable API counts as 0 nodes and keeps the loop going.
  n=$(kubectl get nodes -l "$SELECTOR" -o name 2>/dev/null | wc -l | tr -d ' ') || true
  if [ "$n" -ge "$COUNT" ]; then
    echo "cni-bootstrap: found $n node(s) matching '$label_desc' (needed $COUNT)"
    exit 0
  fi
  if [ "$SECONDS" -ge "$TIMEOUT" ]; then
    echo "cni-bootstrap: timed out after ${TIMEOUT}s waiting for $COUNT node(s) matching '$label_desc' (found $n)" >&2
    exit 1
  fi
  echo "cni-bootstrap: waiting for $COUNT node(s) matching '$label_desc' (found $n)..."
  sleep 10
done
