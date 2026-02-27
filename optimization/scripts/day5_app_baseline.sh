#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day5_app_${TS}"
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
  echo '== java/gunicorn/uvicorn processes =='
  cmd_or_note ps -eo pid,ppid,user,%cpu,%mem,etime,cmd | egrep 'java|gunicorn|uvicorn' | grep -v grep || true

  echo
  echo '== top cpu processes =='
  cmd_or_note ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 30

  echo
  echo '== top mem processes =='
  cmd_or_note ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%mem | head -n 30

  echo
  echo '== socket summary =='
  cmd_or_note ss -s
} > "$OUT/01_process_snapshot.txt" 2>&1

if has_cmd pgrep; then
  JPID=$(pgrep -f 'java' | head -n 1 || true)
else
  JPID=""
fi
if [[ -n "$JPID" ]]; then
  {
    echo "== jcmd VM.flags pid=$JPID =="
    cmd_or_note jcmd "$JPID" VM.flags
    echo
    echo "== jstat -gcutil pid=$JPID =="
    cmd_or_note jstat -gcutil "$JPID" 1s 10
  } > "$OUT/02_java_snapshot.txt" 2>&1
fi

{
  echo "Day5 baseline complete"
  echo "Output: $OUT"
  ls -1 "$OUT"
} > "$OUT/00_summary.txt"

echo "[DONE] $OUT/00_summary.txt"
