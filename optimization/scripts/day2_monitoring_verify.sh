#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day2_monitoring_${TS}"
mkdir -p "$OUT"

PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
TARGET_URL="${TARGET_URL:-}"

echo "[INFO] output: $OUT"
echo "[INFO] PROM_URL: $PROM_URL"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

fetch_head() {
  local name="$1"
  local url="$2"
  local out_file="$OUT/${name}.txt"
  echo "== ${name} =="
  if ! has_cmd curl; then
    echo "curl not found"
    echo
    return 0
  fi
  if curl -fsS "$url" -o "$out_file"; then
    head -n 20 "$out_file" || true
  else
    echo "${name} not reachable: $url"
  fi
  echo
}

{
  echo '== listeners =='
  if has_cmd ss; then
    ss -lntup | egrep '9100|9090|3000|9104|9121|9115' || true
  else
    echo 'ss not found'
  fi
  echo
  echo '== monitoring processes =='
  ps -ef | egrep 'node_exporter|prometheus|grafana|mysqld_exporter|redis_exporter|blackbox_exporter' | grep -v grep || true
} > "$OUT/01_process_ports.txt" 2>&1

{
  fetch_head node_exporter http://127.0.0.1:9100/metrics
  fetch_head mysqld_exporter http://127.0.0.1:9104/metrics
  fetch_head redis_exporter http://127.0.0.1:9121/metrics
} > "$OUT/02_exporters.txt" 2>&1

if has_cmd curl; then
  curl -fsS "$PROM_URL/api/v1/targets" > "$OUT/03_prom_targets.json" || echo '{}' > "$OUT/03_prom_targets.json"
  curl -fsS "$PROM_URL/api/v1/rules" > "$OUT/04_prom_rules.json" || echo '{}' > "$OUT/04_prom_rules.json"
  curl -fsS "$PROM_URL/api/v1/alerts" > "$OUT/05_prom_alerts.json" || echo '{}' > "$OUT/05_prom_alerts.json"
else
  echo '{}' > "$OUT/03_prom_targets.json"
  echo '{}' > "$OUT/04_prom_rules.json"
  echo '{}' > "$OUT/05_prom_alerts.json"
fi

DOWN_COUNT=$(grep -o '"health":"down"' "$OUT/03_prom_targets.json" | wc -l || true)
FIRING_COUNT=$(grep -o '"state":"firing"' "$OUT/05_prom_alerts.json" | wc -l || true)

{
  echo "down_targets=$DOWN_COUNT"
  echo "firing_alerts=$FIRING_COUNT"
  echo
  echo 'rule_keywords_check:'
  egrep -io 'InstanceDown|HighErrorRate|HighLatency|DiskFull|NodeClockSkewDetected' "$OUT/04_prom_rules.json" | sort -u || echo 'no matched keyword'
} > "$OUT/06_summary.txt"

if [[ -n "$TARGET_URL" ]]; then
  {
    echo "== target health =="
    if has_cmd curl; then
      curl -I --max-time 5 "$TARGET_URL" || true
    else
      echo 'curl not found'
    fi
  } > "$OUT/07_target_probe.txt" 2>&1
fi

echo "[DONE] $OUT/06_summary.txt"
