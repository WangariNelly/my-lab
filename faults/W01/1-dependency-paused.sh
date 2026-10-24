#!/usr/bin/env bash
# W01/1 — a shop dependency is frozen (docker pause): requests hang instead of failing.
# Target: the local Docker Compose shop (apps/shop/shop.sh up). Env: SHOP_FAULT_CONTAINER (default currency).
set -euo pipefail
target="${SHOP_FAULT_CONTAINER:-currency}"
case "${1:-}" in
  inject)
    docker inspect "$target" >/dev/null 2>&1 || { echo "container $target not running — start the shop first" >&2; exit 1; }
    [[ "$(docker inspect -f '{{.State.Paused}}' "$target")" == true ]] || docker pause "$target" >/dev/null
    ;;
  revert)
    if [[ "$(docker inspect -f '{{.State.Paused}}' "$target" 2>/dev/null)" == true ]]; then docker unpause "$target" >/dev/null; fi
    echo "reverted"
    ;;
  describe) cat <<'EOT'
Root cause: the currency container was paused (cgroup freezer). Its TCP port still
accepts connections at the kernel level, but nothing answers, so callers wait until
their own timeouts fire. `docker ps` shows "Up … (Paused)".
Signals that should have led you here: Jaeger traces with a long span to currency;
frontend latency up, error rate only slowly rising; docker inspect .State.Paused=true.
Prevention: deadlines/timeouts on every RPC, latency SLO alerts (W24), and container
state in monitoring (paused/restarting are not "healthy").
EOT
  ;;
  *) echo "usage: $0 inject|revert|describe" >&2; exit 2 ;;
esac
