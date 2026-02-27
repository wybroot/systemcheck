# Day 3 安全与基础稳定 SOP

目标：在不影响业务的前提下完成最小安全基线与服务稳定性加固。

## 1. 验收目标（DoD）
- SSH 基线达标（禁 root 直登、禁密码登录、仅密钥）。
- sudo 权限按最小授权收敛。
- 系统日志轮转生效，避免磁盘被日志打满。
- 关键服务具备 systemd 重启策略与资源限制。
- 有可执行回滚步骤并已评审。

## 2. 执行顺序
1) 只读审计
2) 形成变更单（含回滚）
3) 灰度一台
4) 观察 30~60 分钟
5) 分批推广

## 3. 最小安全基线
- SSH：`PermitRootLogin no`、`PasswordAuthentication no`、`PubkeyAuthentication yes`
- 账号：禁共享账号，清理无主账号与过期账号
- sudo：按角色授权，禁止全量免密
- 端口：仅开放业务必需端口
- 审计：保留登录与 sudo 操作审计

## 4. 基础稳定性基线
- systemd：`Restart=always`、`RestartSec=5`、`LimitNOFILE=65535`
- 资源：检查 nofile/nproc 与服务配置一致
- 日志：logrotate 周期、压缩、保留天数明确
- 时间：NTP/Chrony 同步正常

## 5. 风险与回滚
- SSH 变更前必须保留当前会话 + 开新会话验证。
- systemd 变更后先 `daemon-reload`，再单服务重启验证。
- 任何失败按“配置回退 + 服务恢复 + 验证探活”执行。

## 6. 交付物
- 《Day3 安全基线核对表》
- 《变更与回滚记录》
- 《灰度结果与推广计划》
