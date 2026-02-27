#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day6_data_${TS}"
mkdir -p "$OUT"

echo "[INFO] output: $OUT"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_CMD=(mysql --connect-timeout=3 --host "$MYSQL_HOST" --port "$MYSQL_PORT" --user "$MYSQL_USER")
if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
  export MYSQL_PWD="$MYSQL_PASSWORD"
fi

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_CMD=(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT")
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
  REDIS_CMD+=(-a "$REDIS_PASSWORD")
fi

# MySQL
if has_cmd mysql; then
  {
    echo '== mysql global status =='
    "${MYSQL_CMD[@]}" -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';" || true
    "${MYSQL_CMD[@]}" -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" || true
    "${MYSQL_CMD[@]}" -e "SHOW VARIABLES LIKE 'slow_query_log';" || true
    "${MYSQL_CMD[@]}" -e "SHOW VARIABLES LIKE 'long_query_time';" || true
    echo
    echo '== mysql processlist (top 50) =='
    "${MYSQL_CMD[@]}" -e "SHOW PROCESSLIST;" | head -n 50 || true
    echo
    echo '== mysql replica status =='
    "${MYSQL_CMD[@]}" -e "SHOW REPLICA STATUS\\G" 2>/dev/null || "${MYSQL_CMD[@]}" -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
  } > "$OUT/01_mysql.txt" 2>&1
else
  echo 'mysql command not found' > "$OUT/01_mysql.txt"
fi

# Redis
if has_cmd redis-cli; then
  {
    echo '== redis memory =='
    "${REDIS_CMD[@]}" INFO memory || true
    echo
    echo '== redis stats =='
    "${REDIS_CMD[@]}" INFO stats || true
    echo
    echo '== redis commandstats =='
    "${REDIS_CMD[@]}" INFO commandstats || true
    echo
    echo '== redis keyspace =='
    "${REDIS_CMD[@]}" INFO keyspace || true
    echo
    echo '== redis slowlog len =='
    "${REDIS_CMD[@]}" SLOWLOG LEN || true
  } > "$OUT/02_redis.txt" 2>&1
else
  echo 'redis-cli command not found' > "$OUT/02_redis.txt"
fi

{
  echo "Day6 data audit complete"
  echo "Output: $OUT"
  ls -1 "$OUT"
} > "$OUT/00_summary.txt"

echo "[DONE] $OUT/00_summary.txt"
