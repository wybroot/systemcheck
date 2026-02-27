# Day 2 监控补齐清单（命令级）

说明：以下命令默认在 Linux 上执行，重点是“检查接入是否完整”，不改生产配置。
执行前先替换占位符：`your-service.example.com`。

## 1. 检查采集端口与进程
```bash
ss -lntup | egrep '9100|9090|3000|9104|9121|9115' || true
ps -ef | egrep 'node_exporter|prometheus|grafana|mysqld_exporter|redis_exporter|blackbox_exporter' | grep -v grep || true
```

## 2. 检查 exporter 指标端点
```bash
curl -fsS http://127.0.0.1:9100/metrics | head -n 5 || true
curl -fsS http://127.0.0.1:9104/metrics | head -n 5 || true   # mysqld_exporter（如有）
curl -fsS http://127.0.0.1:9121/metrics | head -n 5 || true   # redis_exporter（如有）
```

## 3. 检查 Prometheus 目标状态
```bash
curl -fsS 'http://127.0.0.1:9090/api/v1/targets' > /tmp/prom_targets.json || echo '{}' > /tmp/prom_targets.json
# 快速检查 down 目标数量（无 jq 时可直接 grep）
grep -o '"health":"down"' /tmp/prom_targets.json | wc -l
```

## 4. 检查核心告警规则是否加载
```bash
curl -fsS 'http://127.0.0.1:9090/api/v1/rules' > /tmp/prom_rules.json || echo '{}' > /tmp/prom_rules.json
# 关键关键字（可按你们命名调整）
egrep -i 'InstanceDown|HighErrorRate|HighLatency|DiskFull|NodeClockSkewDetected' /tmp/prom_rules.json || true
```

## 5. 检查告警当前状态
```bash
curl -fsS 'http://127.0.0.1:9090/api/v1/alerts' > /tmp/prom_alerts.json || echo '{}' > /tmp/prom_alerts.json
grep -o '"state":"firing"' /tmp/prom_alerts.json | wc -l
```

## 6. 黑盒探活（HTTP/TCP）
```bash
# 直接探活业务入口
curl -I --max-time 5 https://your-service.example.com/health || true

# 如果使用 blackbox_exporter，检查 probe 指标（示例）
curl -fsS 'http://127.0.0.1:9115/probe?target=https://your-service.example.com/health&module=http_2xx' | egrep 'probe_success|probe_duration_seconds' || true
```

## 7. 核心面板验收项（人工确认）
- 全局看板存在并可见：可用性/QPS/P95/错误率。
- 每个关键服务都能按 `env, service, instance` 过滤。
- 告警面板能看到最近 24h 的触发记录。

## 8. 结果记录模板
- 目标总数：
- down 目标数：
- firing 告警数：
- 缺失的关键指标：
- 今日整改项（P0/P1）：
- 明日计划（Day 3 安全与基础稳定）：
