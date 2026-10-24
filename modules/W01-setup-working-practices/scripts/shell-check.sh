#!/usr/bin/env bash
# Linux shell basics check. Generates a small, realistic sandbox (web access
# logs, a config tree, some large files), prints the tasks, and verifies your
# answers. Everything stays in $SANDBOX (default ~/opslab-shell-check).
#
#   bash shell-check.sh setup     # create the sandbox and print the tasks
#   bash shell-check.sh verify    # check $SANDBOX/answers.txt
#   bash shell-check.sh clean
set -euo pipefail

SANDBOX="${SANDBOX:-$HOME/opslab-shell-check}"

tasks() {
  cat <<EOF
Sandbox: $SANDBOX
Write each answer as key=value in $SANDBOX/answers.txt, using only shell
tools (grep, awk, sort, uniq, find, wc, cut, stat …). No editors, no Python.

  errors=      number of HTTP 5xx responses in logs/access.log
  top_ip=      client IP with the most requests in logs/access.log
  top_path=    most requested path that returned 404
  big_files=   number of files under data/ larger than 1 MiB
  newest=      name (basename only) of the most recently modified file under conf/
  world_writable=  path (relative to the sandbox) of the one world-writable file under conf/
  listen_port= the port value set in conf/app/shop.conf (ignore commented lines)
  unique_ua=   number of distinct user agents in logs/access.log
EOF
}

setup() {
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX"/{logs,data,conf/app,conf/legacy}
  local ips=(10.0.1.11 10.0.1.12 10.0.1.13 203.0.113.7 198.51.100.23)
  local paths=(/ /api/products /api/cart /api/checkout /static/app.js /favicon.ico /old-page)
  local uas=("curl/8.5.0" "Mozilla/5.0" "kube-probe/1.37" "Locust/2.0")
  local codes=(200 200 200 200 201 304 404 500 502 503)
  RANDOM=42
  for _ in $(seq 1 2000); do
    local ip=${ips[RANDOM % ${#ips[@]}]} path=${paths[RANDOM % ${#paths[@]}]}
    local code=${codes[RANDOM % ${#codes[@]}]} ua=${uas[RANDOM % ${#uas[@]}]}
    [[ $path == /old-page ]] && code=404
    printf '%s - - [08/Oct/2026:10:%02d:%02d +0000] "GET %s HTTP/1.1" %s %d "-" "%s"\n' \
      "$ip" $((RANDOM % 60)) $((RANDOM % 60)) "$path" "$code" $((RANDOM % 5000)) "$ua"
  done >"$SANDBOX/logs/access.log"
  for i in 1 2 3; do head -c $((2 * 1024 * 1024)) /dev/zero >"$SANDBOX/data/export-$i.bin"; done
  for i in 1 2 3 4; do head -c 4096 /dev/zero >"$SANDBOX/data/small-$i.bin"; done
  printf '# port=8000\nport=8080\nworkers=4\n' >"$SANDBOX/conf/app/shop.conf"
  printf 'legacy=true\n' >"$SANDBOX/conf/legacy/old.conf"
  touch -d '2026-01-01' "$SANDBOX/conf/legacy/old.conf" "$SANDBOX/conf/app/shop.conf"
  printf 'token=redacted\n' >"$SANDBOX/conf/app/secrets.conf"
  chmod 0666 "$SANDBOX/conf/app/secrets.conf"
  touch "$SANDBOX/answers.txt"
  tasks
}

expected() {
  local log="$SANDBOX/logs/access.log"
  echo "errors=$(awk '$9 ~ /^5/' "$log" | wc -l | tr -d ' ')"
  echo "top_ip=$(awk '{print $1}' "$log" | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')"
  echo "top_path=$(awk '$9==404 {print $7}' "$log" | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')"
  echo "big_files=$(find "$SANDBOX/data" -type f -size +1M | wc -l | tr -d ' ')"
  echo "newest=$(find "$SANDBOX/conf" -type f -printf '%T@ %f\n' | sort -rn | awk 'NR==1{print $2}')"
  echo "world_writable=conf/app/secrets.conf"
  echo "listen_port=$(grep -E '^port=' "$SANDBOX/conf/app/shop.conf" | cut -d= -f2)"
  echo "unique_ua=$(awk -F'"' '{print $6}' "$log" | sort -u | wc -l | tr -d ' ')"
}

verify() {
  [[ -f "$SANDBOX/answers.txt" ]] || { echo "run setup first" >&2; exit 1; }
  local pass=0 total=0
  while IFS='=' read -r key want; do
    total=$((total + 1))
    got="$(grep -E "^$key=" "$SANDBOX/answers.txt" | tail -1 | cut -d= -f2- || true)"
    if [[ "$got" == "$want" ]]; then
      pass=$((pass + 1)); echo "PASS $key"
    else
      echo "FAIL $key (you: '${got}')"
    fi
  done < <(expected)
  echo "$pass/$total correct"
  [[ $pass -eq $total ]] || { echo "Revisit the failing ones; the W02 module assumes all of this."; exit 1; }
  echo "Shell basics: ready for W02. Now explain the pipeline you used for top_ip to someone else."
}

case "${1:-}" in
  setup) setup ;;
  verify) verify ;;
  clean) rm -rf "$SANDBOX" ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
