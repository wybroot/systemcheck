# Day 3 安全与基础稳定检查清单（命令级）

说明：优先只读检查；涉及配置修改时，先出变更单再执行。
执行前先替换占位符：`<username>`、`<service_name>`。

## 1. SSH 基线检查
```bash
sshd -T | egrep 'permitrootlogin|passwordauthentication|pubkeyauthentication'
```

## 2. 账号与权限检查
```bash
# 可登录账号
awk -F: '($7!~/nologin|false/){print $1":"$7}' /etc/passwd

# sudo 授权
ls -l /etc/sudoers /etc/sudoers.d
sudo -l -U <username>
```

## 3. 端口暴露检查
```bash
ss -lntup
iptables -S 2>/dev/null || true
nft list ruleset 2>/dev/null || true
```

## 4. 日志与磁盘风险检查
```bash
journalctl --disk-usage
df -hT
df -i
ls -lh /etc/logrotate.conf /etc/logrotate.d
logrotate -d /etc/logrotate.conf | head -n 80
```

## 5. systemd 稳定性检查
```bash
systemctl --failed --no-pager
systemctl show <service_name> -p Restart -p RestartSec -p LimitNOFILE -p TimeoutStopUSec
```

## 6. 时间同步检查
```bash
timedatectl
chronyc tracking 2>/dev/null || true
chronyc sources -v 2>/dev/null || true
```

## 7. 回滚前置（必须）
```bash
# 修改前备份
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%H%M%S)
# 语法检查
sudo sshd -t
```

## 8. 结果模板
- SSH 基线：通过/不通过
- sudo 最小授权：通过/不通过
- 端口暴露：通过/不通过
- systemd 稳定性：通过/不通过
- 今日变更项：
- 回滚点：
