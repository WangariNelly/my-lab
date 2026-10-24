#!/usr/bin/env bash
# W01/2 — a stale /etc/hosts override sends the ServiceNow instance name to a dead address.
# Env: SN_INSTANCE (https://devNNNNN.service-now.com). Needs sudo in the devcontainer.
set -euo pipefail
marker="# opslab-fault-W01-2"
host="$(sed -E 's#^https?://##; s#/.*$##' <<<"${SN_INSTANCE:?SN_INSTANCE must be set}")"
case "${1:-}" in
  inject)
    grep -q "$marker" /etc/hosts || echo "192.0.2.10 $host $marker" | sudo tee -a /etc/hosts >/dev/null
    ;;
  revert)
    if grep -q "$marker" /etc/hosts; then
      tmp="$(mktemp)"; grep -v "$marker" /etc/hosts >"$tmp"; sudo cp "$tmp" /etc/hosts; rm -f "$tmp"
    fi
    echo "reverted"
    ;;
  describe) cat <<'EOT'
Root cause: a static /etc/hosts entry maps the ServiceNow instance hostname to
192.0.2.10 (TEST-NET, unroutable). The browser on your laptop uses your laptop's
resolver, so the instance "works" there; the devcontainer uses /etc/hosts first.
Signals: connection timeouts only from the container; `getent hosts <instance>`
disagrees with `dig +short <instance>` (dig bypasses /etc/hosts, getent doesn't).
Prevention: never pin SaaS endpoints in hosts files; know the resolution order
(/etc/nsswitch.conf "hosts: files dns").
EOT
  ;;
  *) echo "usage: $0 inject|revert|describe" >&2; exit 2 ;;
esac
