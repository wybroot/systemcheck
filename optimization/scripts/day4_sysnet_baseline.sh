#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day4_sysnet_${TS}"
mkdir -p "$OUT"

echo "[INFO] output: $OUT"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cmd_or_note() {
  local cmd="$1"
  shift || true
  if has_cmd "$cmd"; then
    "$cmd" "$@" || true
  else
    echo "$cmd not found"
  fi
}

{
  echo '== sysctl snapshot =='
  cmd_or_note sysctl -a | egrep 'fs.file-max|somaxconn|tcp_max_syn_backlog|ip_local_port_range|tcp_fin_timeout|tcp_tw_reuse' || true

  echo
  echo '== limits =='
  ulimit -n || true

  echo
  echo '== network summary =='
  cmd_or_note ss -s

  echo
  echo '== vmstat =='
  cmd_or_note vmstat 1 10

  echo
  echo '== iostat =='
  cmd_or_note iostat -x 1 5

  echo
  echo '== sar tcp/dev =='
  cmd_or_note sar -n TCP,DEV 1 5
} > "$OUT/01_before_change_snapshot.txt" 2>&1

{
  echo "Day4 baseline complete"
  echo "Output: $OUT"
  ls -1 "$OUT"
} > "$OUT/00_summary.txt"

echo "[DONE] $OUT/00_summary.txt"
