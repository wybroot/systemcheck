# Day 1 只读体检清单（命令级）

适用范围：Linux 生产服务器接管首日。
原则：只读检查，不改配置，不重启服务。

## 0. 执行约束
- 在业务低峰执行。
- 所有输出落盘到 `/tmp/day1_audit_$(date +%F_%H%M%S)`。
- 不执行任何会写系统配置的命令（例如 `sysctl -w`、`systemctl restart`、`sed -i`）。

## 1. 建立审计目录
```bash
TS=$(date +%F_%H%M%S)
OUT="/tmp/day1_audit_${TS}"
mkdir -p "$OUT"
echo "$OUT"
```

## 2. 系统与硬件资产盘点
```bash
{
  echo '== hostname =='; hostnamectl || hostname
  echo '== os =='; cat /etc/os-release
  echo '== kernel =='; uname -a
  echo '== uptime =='; uptime
  echo '== cpu =='; lscpu
  echo '== memory =='; free -h
  echo '== block devices =='; lsblk -f
  echo '== mounts =='; findmnt -D
} > "$OUT/01_inventory.txt" 2>&1
```

## 3. 资源风险检查（磁盘 / inode / OOM / 句柄）
```bash
{
  echo '== disk usage =='; df -hT
  echo '== inode usage =='; df -i
  echo '== top dirs in /var (size) =='; du -xh --max-depth=1 /var 2>/dev/null | sort -h | tail -n 20
  echo '== open files limit =='; ulimit -n
  echo '== fs.file-max =='; sysctl fs.file-max
  echo '== dmesg oom =='; dmesg -T | grep -Ei 'out of memory|killed process' | tail -n 100
} > "$OUT/02_risk_storage_oom_fd.txt" 2>&1
```

## 4. 进程与服务健康
```bash
{
  echo '== top cpu processes =='; ps -eo pid,ppid,user,%cpu,%mem,stat,lstart,cmd --sort=-%cpu | head -n 30
  echo '== top mem processes =='; ps -eo pid,ppid,user,%cpu,%mem,stat,lstart,cmd --sort=-%mem | head -n 30
  echo '== zombie processes =='; ps -eo pid,ppid,stat,cmd | awk '$3 ~ /Z/ {print}'
  echo '== failed services =='; systemctl --failed --no-pager
  echo '== restart counters =='; systemctl list-units --type=service --state=running --no-pager
} > "$OUT/03_process_service_health.txt" 2>&1
```

## 5. CPU / 内存 / IO / 网络即时快照
```bash
{
  echo '== vmstat =='; vmstat 1 5
  echo '== iostat =='; iostat -x 1 3
  echo '== mpstat =='; mpstat -P ALL 1 3
  echo '== sar network =='; sar -n DEV 1 3
} > "$OUT/04_runtime_snapshot.txt" 2>&1
```

> 若 `iostat/mpstat/sar` 不存在，先记录“工具缺失”，不要临时安装。

## 6. 网络连接与端口暴露
```bash
{
  echo '== listening ports =='; ss -lntup
  echo '== tcp summary =='; ss -s
  echo '== established top peers =='; ss -ant | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 30
  echo '== iptables =='; iptables -S 2>/dev/null || true
  echo '== nft ruleset =='; nft list ruleset 2>/dev/null || true
} > "$OUT/05_network_exposure.txt" 2>&1
```

## 7. 时间同步与证书有效期
```bash
{
  echo '== timedatectl =='; timedatectl
  echo '== chrony tracking =='; chronyc tracking 2>/dev/null || true
  echo '== chrony sources =='; chronyc sources -v 2>/dev/null || true
} > "$OUT/06_time_sync.txt" 2>&1
```

证书（按你们证书路径替换）：
```bash
CERT=/etc/nginx/ssl/server.crt
[ -f "$CERT" ] && openssl x509 -in "$CERT" -noout -dates -issuer -subject > "$OUT/07_cert_check.txt"
```

## 8. 安全基线只读检查
```bash
{
  echo '== sshd_config key items =='
  egrep -i 'PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|AllowGroups' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
  echo '== sudoers include =='; ls -l /etc/sudoers /etc/sudoers.d 2>/dev/null
  echo '== recent auth log =='; tail -n 200 /var/log/auth.log 2>/dev/null || tail -n 200 /var/log/secure 2>/dev/null
} > "$OUT/08_security_baseline.txt" 2>&1
```

## 9. 应用与日志体量检查
```bash
{
  echo '== system journal size =='; journalctl --disk-usage
  echo '== nginx logs =='; ls -lh /var/log/nginx 2>/dev/null || true
  echo '== app logs (customize path) =='; ls -lh /var/log 2>/dev/null | head -n 50
} > "$OUT/09_log_volume.txt" 2>&1
```

## 10. 快速风险判定阈值（首日版）
- 磁盘使用率 > 80%：中风险；> 90%：高风险。
- inode 使用率 > 70%：中风险；> 85%：高风险。
- `iowait` 持续 > 20%：高风险。
- `OOM` 7 天内出现：高风险。
- 服务频繁重启（1 小时内 >= 3 次）：高风险。
- NTP 未同步：高风险。
- 生产开放非必要管理端口：高风险。

## 11. 产出模板（发给团队）
- 主机信息：
- 高风险项（P0）：
- 中风险项（P1）：
- 低风险项（P2）：
- 今日不处理但需排期：
- 明日计划（Day 2 监控补齐）：

## 12. 一键采集（可选）
将上面命令整理到 `day1_audit.sh`，执行：
```bash
bash scripts/day1_audit.sh
```

执行后提交目录：
```bash
tar -czf "${OUT}.tar.gz" -C /tmp "$(basename "$OUT")"
```
