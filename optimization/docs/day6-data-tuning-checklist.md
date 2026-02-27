# Day 6 数据层调优检查清单

说明：建议先设置连接参数，避免误连：
```bash
export MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 MYSQL_USER=root
export REDIS_HOST=127.0.0.1 REDIS_PORT=6379
export MYSQL_PASSWORD=your_mysql_password   # 可选
export REDIS_PASSWORD=your_redis_password   # 可选
[ -n "$MYSQL_PASSWORD" ] && export MYSQL_PWD="$MYSQL_PASSWORD"
```

## 1. MySQL 只读检查
```bash
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';"
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW VARIABLES LIKE 'slow_query_log';"
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW VARIABLES LIKE 'long_query_time';"
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW PROCESSLIST;" | head -n 50
```

## 2. 慢查询与执行计划
```bash
# 根据实际路径调整
ls -lh /var/log/mysql/*slow*.log 2>/dev/null || true
# 示例：对慢 SQL 做 explain
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "EXPLAIN FORMAT=TRADITIONAL <your_sql>;"
```

## 3. 复制与高可用（如有）
```bash
mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW REPLICA STATUS\\G" 2>/dev/null || mysql --connect-timeout=3 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SHOW SLAVE STATUS\\G" 2>/dev/null
```

## 4. Redis 只读检查
```bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO stats
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO commandstats
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SLOWLOG LEN
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO keyspace
```

## 5. Redis 热点/大 Key（按需）
```bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --bigkeys
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --hotkeys   # 仅在支持版本与配置允许时
```

## 6. 备份与恢复链路检查
- 最近一次备份时间：
- 最近一次恢复演练时间：
- 演练结果（RTO/RPO）：

## 7. 输出模板
- MySQL 慢查询结论：
- MySQL 索引改进项：
- Redis 内存策略结论：
- 风险项与排期：
