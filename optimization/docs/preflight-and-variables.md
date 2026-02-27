# 执行前检查（Preflight）

在执行 Day1~Day7 脚本前，建议先确认以下事项，避免“脚本无输出/误判”。

## 1. 基础前置
- 已在目标 Linux 主机执行（非本机 Windows）。
- 具备只读巡检权限；涉及变更项具备 sudo 权限。
- 业务方确认变更窗口（Day3+）。

## 2. 常用命令依赖（按需）
- 必要：`bash`、`ps`、`ss`、`curl`、`systemctl`、`journalctl`
- 推荐：`iostat`、`mpstat`、`sar`（sysstat）、`chronyc`
- 数据层：`mysql`、`redis-cli`

## 3. 统一输出目录
所有脚本默认输出到 `/tmp/dayX_*`。
执行后建议归档到：
```bash
mkdir -p ~/ops-audit-reports
cp -r /tmp/day*_*/ ~/ops-audit-reports/
```

## 4. 可选环境变量（脚本支持）

### Day2
```bash
export PROM_URL=http://127.0.0.1:9090
export TARGET_URL=https://your-service.example.com/health
```

### Day6
```bash
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_USER=root
export MYSQL_PASSWORD=your_mysql_password   # 可选
export REDIS_HOST=127.0.0.1
export REDIS_PORT=6379
export REDIS_PASSWORD=your_redis_password   # 可选
```

### Day1 证书路径
```bash
export CERT_PATH=/etc/nginx/ssl/server.crt
```

## 5. 占位符替换提醒
执行前请替换文档中的占位符：
- `<username>`
- `<service_name>`
- `<process_keyword>`
- `<your_sql>`
- `your-service.example.com`
