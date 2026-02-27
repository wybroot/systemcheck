#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day1_audit_${TS}"
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

run_or_note() {
  local name="$1"
  shift
  {
    echo "== ${name} =="
    "$@"
    echo
  } >> "$OUT/04_runtime_snapshot.txt" 2>&1 || true
}

{
  echo '== hostname =='; if has_cmd hostnamectl; then hostnamectl || true; else cmd_or_note hostname; fi
  echo '== os =='; cmd_or_note cat /etc/os-release
  echo '== kernel =='; cmd_or_note uname -a
  echo '== uptime =='; cmd_or_note uptime
  echo '== cpu =='; cmd_or_note lscpu
  echo '== memory =='; cmd_or_note free -h
  echo '== block devices =='; cmd_or_note lsblk -f
  echo '== mounts =='; cmd_or_note findmnt -D
} > "$OUT/01_inventory.txt" 2>&1

{
  echo '== disk usage =='; cmd_or_note df -hT
  echo '== inode usage =='; cmd_or_note df -i
  echo '== top dirs in /var (size) =='; cmd_or_note du -xh --max-depth=1 /var 2>/dev/null | sort -h | tail -n 20
  echo '== open files limit =='; ulimit -n || true
  echo '== fs.file-max =='; cmd_or_note sysctl fs.file-max
  echo '== dmesg oom =='; cmd_or_note dmesg -T | grep -Ei 'out of memory|killed process' | tail -n 100 || true
} > "$OUT/02_risk_storage_oom_fd.txt" 2>&1

{
  echo '== top cpu processes =='; cmd_or_note ps -eo pid,ppid,user,%cpu,%mem,stat,lstart,cmd --sort=-%cpu | head -n 30
  echo '== top mem processes =='; cmd_or_note ps -eo pid,ppid,user,%cpu,%mem,stat,lstart,cmd --sort=-%mem | head -n 30
  echo '== zombie processes =='; cmd_or_note ps -eo pid,ppid,stat,cmd | awk '$3 ~ /Z/ {print}'
  echo '== failed services =='; cmd_or_note systemctl --failed --no-pager
  echo '== running services =='; cmd_or_note systemctl list-units --type=service --state=running --no-pager
} > "$OUT/03_process_service_health.txt" 2>&1

: > "$OUT/04_runtime_snapshot.txt"
if has_cmd vmstat; then run_or_note vmstat vmstat 1 5; else echo 'vmstat not found' >> "$OUT/04_runtime_snapshot.txt"; fi
if has_cmd iostat; then run_or_note iostat iostat -x 1 3; else echo 'iostat not found' >> "$OUT/04_runtime_snapshot.txt"; fi
if has_cmd mpstat; then run_or_note mpstat mpstat -P ALL 1 3; else echo 'mpstat not found' >> "$OUT/04_runtime_snapshot.txt"; fi
if has_cmd sar; then run_or_note 'sar -n DEV' sar -n DEV 1 3; else echo 'sar not found' >> "$OUT/04_runtime_snapshot.txt"; fi

{
  echo '== listening ports =='; cmd_or_note ss -lntup
  echo '== tcp summary =='; cmd_or_note ss -s
  echo '== established top peers =='; cmd_or_note ss -ant | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 30
  echo '== iptables =='; cmd_or_note iptables -S
  echo '== nft ruleset =='; cmd_or_note nft list ruleset
} > "$OUT/05_network_exposure.txt" 2>&1

{
  echo '== timedatectl =='; cmd_or_note timedatectl
  echo '== chrony tracking =='; cmd_or_note chronyc tracking
  echo '== chrony sources =='; cmd_or_note chronyc sources -v
} > "$OUT/06_time_sync.txt" 2>&1

{
  echo '== sshd_config key items =='
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    cmd_or_note egrep -i 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|AllowGroups' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf
  else
    cmd_or_note egrep -i 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|AllowGroups' /etc/ssh/sshd_config
  fi
  echo '== sudoers include =='; cmd_or_note ls -l /etc/sudoers /etc/sudoers.d
  echo '== recent auth log =='
  if [[ -f /var/log/auth.log ]]; then
    tail -n 200 /var/log/auth.log || true
  elif [[ -f /var/log/secure ]]; then
    tail -n 200 /var/log/secure || true
  else
    echo "auth log not found"
  fi
} > "$OUT/08_security_baseline.txt" 2>&1

{
  echo '== system journal size =='; cmd_or_note journalctl --disk-usage
  echo '== nginx logs =='; cmd_or_note ls -lh /var/log/nginx
  echo '== /var/log sample =='; cmd_or_note ls -lh /var/log | head -n 50
} > "$OUT/09_log_volume.txt" 2>&1

CERT_PATH="${CERT_PATH:-/etc/nginx/ssl/server.crt}"
if [[ -f "$CERT_PATH" ]]; then
  cmd_or_note openssl x509 -in "$CERT_PATH" -noout -dates -issuer -subject > "$OUT/07_cert_check.txt" 2>&1
else
  echo "cert not found: $CERT_PATH" > "$OUT/07_cert_check.txt"
fi

SUMMARY="$OUT/00_summary.txt"
{
  echo "Day1 audit complete"
  echo "Output directory: $OUT"
  echo
  echo "Files:"
  ls -1 "$OUT"
} > "$SUMMARY"

echo "[DONE] $SUMMARY"
