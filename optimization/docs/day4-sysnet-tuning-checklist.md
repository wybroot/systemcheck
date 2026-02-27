# Day 4 系统与网络调优清单（灰度执行）

执行前先替换占位符：`<service_name>`、`<process_keyword>`。

## 1. 变更前采样（至少 30 分钟）
```bash
vmstat 1 30
iostat -x 1 30
ss -s
sar -n TCP,DEV 1 30
```

## 2. 备份当前配置
```bash
sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F_%H%M%S)
sudo cp -r /etc/sysctl.d /etc/sysctl.d.bak.$(date +%F_%H%M%S)
```

## 3. 写入灰度参数文件
```bash
sudo tee /etc/sysctl.d/99-prod-tuning.conf >/dev/null <<'EOF'
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 10240 65535
EOF

sudo sysctl --system
```

## 4. 验证参数生效
```bash
sysctl fs.file-max
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv4.ip_local_port_range
```

## 5. 应用服务句柄检查
```bash
systemctl show <service_name> -p LimitNOFILE
cat /proc/$(pgrep -f '<process_keyword>' | head -n1)/limits | grep 'open files'
```

## 6. 观察期（60 分钟）
- 关注 QPS、P95/P99、5xx、连接失败、重传率。
- 若异常达到回滚标准，立即回滚。

## 7. 回滚命令
```bash
sudo rm -f /etc/sysctl.d/99-prod-tuning.conf
sudo sysctl --system
```

## 8. 结果模板
- 灰度实例：
- 变更项：
- 观察结论：通过/回滚
- 推广计划：
