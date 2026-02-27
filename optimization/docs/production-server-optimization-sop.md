# 生产服务器优化 SOP（运维接管版）

## 1. 目标定义（P0）
在任何优化之前，先明确四个核心目标：
- 可用性（Availability）
- 延迟（P95 / P99）
- 错误率（Error Rate）
- 恢复能力（RTO / RPO）

> 原则：生产优化优先级是“稳定性 > 可观测性 > 可恢复性 > 性能”。

---

## 2. 接管当天：只读体检（P0）

### 2.1 资产盘点
- 操作系统版本、内核版本
- CPU / 内存 / 磁盘规格
- 文件系统与挂载参数
- 核心业务进程、启动方式、依赖服务
- 网络拓扑与入口（LB / Nginx / Service Mesh）

### 2.2 风险排查
- 磁盘空间与 inode 使用率
- OOM 历史、僵尸进程
- 句柄使用（nofile）
- NTP/Chrony 时间同步
- TLS/证书有效期
- 异常重启与崩溃日志

### 2.3 安全基线
- 禁止 root 远程直登
- SSH 仅允许密钥登录
- sudo 最小权限
- 最小端口暴露
- 审计日志开启

### 2.4 交付物
- 《现状与风险分级报告》（高/中/低）

---

## 3. 监控与基线建设（P0）

### 3.1 主机指标
- CPU：使用率、load、上下文切换
- 内存：已用、缓存、swap、major fault
- 磁盘：IOPS、await、util、队列长度
- 网络：吞吐、丢包、重传、连接状态

### 3.2 应用指标
- QPS、P95/P99 延迟
- 4xx/5xx、超时率
- 下游依赖成功率
- 队列积压、线程池/连接池水位

### 3.3 数据层指标
- MySQL：慢查询、连接数、锁等待、主从延迟
- Redis：命中率、内存碎片率、慢命令、bigkey/hotkey

### 3.4 基线周期
- 至少覆盖 1 个完整业务峰值周期（建议 3~7 天）

### 3.5 交付物
- 统一看板（主机/应用/数据库）
- 告警分级与响应人

---

## 4. 系统层优化基线（P1）

## 4.1 sysctl 建议（初始模板）
文件：`/etc/sysctl.d/99-prod.conf`

```conf
vm.swappiness = 10
vm.max_map_count = 262144
fs.file-max = 2097152

net.core.somaxconn = 65535
net.core.netdev_max_backlog = 32768

net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
```

> 注意：以上为起步值，必须结合业务压测与实流量验证，禁止一次性大范围调参。

### 4.2 句柄与进程限制
文件：`/etc/security/limits.d/99-prod.conf`

```conf
* soft nofile 65535
* hard nofile 65535
* soft nproc  65535
* hard nproc  65535
```

### 4.3 systemd 服务建议
- `Restart=always`
- `RestartSec=5`
- `LimitNOFILE=65535`
- `TimeoutStopSec=30`
- `KillMode=mixed`

### 4.4 日志与时间
- 配置 logrotate 防止日志打满磁盘
- 时间同步（NTP/Chrony）必须稳定

---

## 5. 网络与 Nginx 优化（P1）

### 5.1 Nginx 基线模板

```nginx
worker_processes auto;
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    keepalive_requests 10000;

    client_header_timeout 10s;
    client_body_timeout 10s;
    send_timeout 30s;

    upstream app {
        server 127.0.0.1:8080;
        keepalive 128;
    }
}
```

### 5.2 重点动作
- 合理配置 upstream keepalive
- 设置连接/请求超时，避免无限等待
- 配置限流与并发保护，防止突发流量击穿

---

## 6. 应用层优化（P1）

### 6.1 Java
- `Xms = Xmx`（降低运行期抖动）
- 建议 G1（`-XX:+UseG1GC`）
- 开启 GC 日志、OOM dump
- 线程池/连接池设上限与超时

### 6.2 Python（Gunicorn/Uvicorn）
- Gunicorn workers 初值：`2 * CPU + 1`（同步模型）
- `timeout` 与 `graceful_timeout` 明确配置
- 访问日志与错误日志可关联 request id

### 6.3 通用稳定性机制
- 超时、重试（退避）、熔断、限流、降级
- 幂等设计，防止重试导致数据重复

---

## 7. 数据层优化（P1）

### 7.1 MySQL
- `slow_query_log=ON`
- `long_query_time=0.5~1s`
- `innodb_buffer_pool_size`（专用库机可从 50%~70% 内存起步）
- 慢 SQL 与索引持续治理

### 7.2 Redis
- 必配 `maxmemory` + `maxmemory-policy`
- 明确 AOF / RDB 持久化策略
- 监控 bigkey/hotkey 与慢命令

### 7.3 备份恢复
- 不仅要“备份成功”，必须“恢复演练成功”

---

## 8. 变更执行规范（P0）
- 一次只改一类参数
- 每次变更都准备回滚点
- 在变更窗口内执行
- 先灰度，观察 30~60 分钟后再全量
- 变更单必须包含：目标、影响面、验证项、回滚步骤

---

## 9. 7 天落地推进计划

### Day 1：只读体检
- 资产盘点、风险扫描
- 产出：《现状与风险清单》

### Day 2：监控补齐
- 接入主机/应用/数据库指标
- 产出：核心看板与告警规则

### Day 3：安全与基础稳定
- SSH、权限、日志轮转、systemd 策略
- 产出：安全基线与回滚说明

### Day 4：系统/网络灰度调优
- 上线 sysctl 与 nofile（单机灰度）
- 产出：调优前后对比

### Day 5：应用层调优
- 线程池/连接池/超时/重试/限流
- 产出：高峰期 P95 与错误率改善报告

### Day 6：数据层调优
- 慢查询治理、索引优化、缓存策略确认
- 产出：慢查询下降与命中率对比

### Day 7：容灾演练
- 备份恢复演练 + 故障切换演练
- 产出：RTO/RPO 实测报告 + Runbook 定稿

---

## 10. 完成定义（Definition of Done）
- 有可执行 Runbook（告警 → 定位 → 止血 → 恢复）
- 有告警分级与值班响应时限
- 有容量预测（1/3/6 个月）
- 有月度恢复演练记录

---

## 11. 附：执行原则（必须遵守）
1. 没有基线，不做优化。
2. 没有回滚，不做变更。
3. 没有监控，不做上线。
4. 没有演练，不算容灾。


---

## 12. 配套文档与脚本
- Day 1 命令级清单：`docs/day1-readonly-checklist.md`
- Day 1 自动采集脚本：`scripts/day1_audit.sh`
- Day 2 监控补齐 SOP：`docs/day2-monitoring-sop.md`
- Day 2 命令级检查清单：`docs/day2-monitoring-checklist.md`
- Day 2 监控验证脚本：`scripts/day2_monitoring_verify.sh`
- Day 3 安全与稳定 SOP：`docs/day3-security-stability-sop.md`
- Day 3 命令级检查清单：`docs/day3-security-stability-checklist.md`
- Day 3 安全审计脚本：`scripts/day3_security_stability_audit.sh`
- Day 4 系统网络调优 SOP：`docs/day4-sysnet-tuning-sop.md`
- Day 4 调优执行清单：`docs/day4-sysnet-tuning-checklist.md`
- Day 4 基线采样脚本：`scripts/day4_sysnet_baseline.sh`
- Day 5 应用调优 SOP：`docs/day5-app-tuning-sop.md`
- Day 5 调优检查清单：`docs/day5-app-tuning-checklist.md`
- Day 5 应用基线脚本：`scripts/day5_app_baseline.sh`
- Day 6 数据层调优 SOP：`docs/day6-data-tuning-sop.md`
- Day 6 数据检查清单：`docs/day6-data-tuning-checklist.md`
- Day 6 数据审计脚本：`scripts/day6_data_audit.sh`
- Day 7 容灾演练 SOP：`docs/day7-drill-sop.md`
- Day 7 演练检查清单：`docs/day7-drill-checklist.md`
- Day 7 演练记录脚本：`scripts/day7_drill_record.sh`
- 推进跟踪表：`docs/rollout-tracker.md`
- 执行前检查与变量说明：`docs/preflight-and-variables.md`
