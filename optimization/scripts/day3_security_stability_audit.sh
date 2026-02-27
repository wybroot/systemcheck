#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day3_security_${TS}"
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
  echo '== sshd baseline =='
  if has_cmd sshd; then
    sshd -T 2>/dev/null | egrep 'permitrootlogin|passwordauthentication|pubkeyauthentication' || true
  else
    echo 'sshd not found'
  fi

  echo
  echo '== accounts =='
  cmd_or_note awk -F: '($7!~/nologin|false/){print $1":"$7}' /etc/passwd

  echo
  echo '== sudoers =='
  cmd_or_note ls -l /etc/sudoers /etc/sudoers.d

  echo
  echo '== listening ports =='
  cmd_or_note ss -lntup

  echo
  echo '== firewall =='
  cmd_or_note iptables -S
  cmd_or_note nft list ruleset

  echo
  echo '== logs and disk =='
  cmd_or_note journalctl --disk-usage
  cmd_or_note df -hT
  cmd_or_note df -i
  cmd_or_note ls -lh /etc/logrotate.conf /etc/logrotate.d

  echo
  echo '== failed services =='
  cmd_or_note systemctl --failed --no-pager

  echo
  echo '== time sync =='
  cmd_or_note timedatectl
  cmd_or_note chronyc tracking
  cmd_or_note chronyc sources -v
} > "$OUT/01_audit.txt" 2>&1

{
  echo "Day3 audit complete"
  echo "Output: $OUT"
  ls -1 "$OUT"
} > "$OUT/00_summary.txt"

echo "[DONE] $OUT/00_summary.txt"
