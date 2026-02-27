# 服务器一键巡检系统

## 项目概述

服务器一键巡检系统是一个完整的服务器运维巡检解决方案，支持从跳板机批量巡检多台服务器。

### 使用场景

```
┌─────────────┐      SSH       ┌─────────────┐
│   跳板机 A   │ ──────────────→│  服务器 B   │
│  执行脚本    │ ──────────────→│  服务器 C   │
│             │ ──────────────→│  服务器 D   │
└─────────────┘                └─────────────┘
```

在跳板机上执行巡检脚本，通过 SSH 远程巡检目标服务器并生成报告。

### 功能特性

- **三阶段架构**：Shell脚本 → Web平台 → 定时告警
- **7大检查模块**：系统、CPU、内存、磁盘、网络、进程、安全
- **并发巡检**：支持多服务器并发执行
- **多种报告格式**：HTML、JSON、TEXT
- **告警通知**：钉钉、企微、邮件、Webhook

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| Shell | Bash 4+ | 巡检脚本 |
| Python | 3.11+ | Web后端 |
| Flask | 3.0 | Web框架 |
| PostgreSQL | 18 | 数据库 |
| Redis | 7 | 缓存 |
| MinIO | Latest | 文件存储 |
| Grafana | 11.0 | 可视化 |

---

## 快速开始

### 前置条件

1. **安装依赖工具（跳板机）**

```bash
# CentOS/RHEL
yum install -y sshpass

# Ubuntu/Debian
apt install -y sshpass
```

2. **配置服务器清单**

编辑 `config/servers.csv`：

```csv
ip,hostname,ssh_port,ssh_user,ssh_password,business,env,services,tags
192.168.1.10,web-server01,22,root,,Web服务,生产,nginx|mysql,
192.168.1.11,db-server01,22,root,YourPassword123,数据库,生产,mysql|redis,
192.168.1.12,app-server01,22,appuser,AppPass456,应用服务,测试,java|tomcat,
```

**字段说明**：
| 字段 | 必填 | 说明 |
|------|------|------|
| ip | 是 | 服务器IP地址 |
| hostname | 是 | 主机名 |
| ssh_port | 否 | SSH端口，默认22 |
| ssh_user | 否 | SSH用户，默认root |
| ssh_password | 否 | SSH密码，**为空则使用免密登录** |
| business | 否 | 业务名称 |
| env | 否 | 环境：生产/测试/开发 |
| services | 否 | 服务列表，用|分隔 |
| tags | 否 | 标签 |

**登录方式**：
- `ssh_password` 为空：使用 SSH 免密登录（需提前配置）
- `ssh_password` 有值：使用密码登录（需安装 sshpass）

3. **SSH免密登录配置（可选）**

如果使用免密登录，需提前配置：

```bash
# 在跳板机上生成密钥（如未生成）
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# 将公钥复制到目标服务器
ssh-copy-id root@192.168.1.10
ssh-copy-id root@192.168.1.11

# 测试连接
ssh root@192.168.1.10 "hostname"
```

### 第一阶段：Shell脚本巡检

```bash
# 巡检所有服务器（从 servers.csv 读取）
./inspect.sh -a

# 巡检指定服务器
./inspect.sh 192.168.1.10 192.168.1.11

# 并发巡检（10个并发）
./inspect.sh -a -p 10

# 只检查CPU和内存
./inspect.sh -a -m cpu,mem

# 生成JSON报告
./inspect.sh -a -r json

# 生成报告并发送邮件
./inspect.sh -a -r html -e admin@example.com
```

### 命令行参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-a, --all` | 巡检所有服务器 | `./inspect.sh -a` |
| `-f, --file` | 指定服务器清单 | `./inspect.sh -f my_servers.csv` |
| `-o, --output` | 指定报告目录 | `./inspect.sh -a -o /tmp/reports` |
| `-r, --report` | 报告格式：html/json/text | `./inspect.sh -a -r json` |
| `-t, --timeout` | SSH超时时间(秒) | `./inspect.sh -a -t 60` |
| `-p, --parallel` | 并发数量 | `./inspect.sh -a -p 10` |
| `-m, --module` | 指定检查模块 | `./inspect.sh -a -m cpu,mem,disk` |
| `-e, --email` | 发送邮件 | `./inspect.sh -a -e admin@xx.com` |
| `-l, --list` | 列出服务器清单 | `./inspect.sh -l` |
| `-v, --verbose` | 详细输出 | `./inspect.sh -a -v` |

### 退出码

| 退出码 | 说明 |
|--------|------|
| 0 | 全部正常 |
| 1 | 存在警告 |
| 2 | 存在严重问题 |

---

## 第二阶段：Web管理平台

### Docker部署（推荐）

```bash
# 复制配置文件
cp .env.example .env

# 修改配置（生产环境必须修改密码）
vim .env

# 启动服务
docker-compose up -d

# 查看状态
docker-compose ps
```

### 服务访问

| 服务 | 地址 | 默认账号 |
|------|------|----------|
| Web界面 | http://localhost:5000 | admin / admin123 |
| Grafana | http://localhost:3000 | admin / admin123 |
| MinIO | http://localhost:9001 | minioadmin / minioadmin |

### Web功能

- **仪表盘**：服务器状态概览
- **服务器管理**：添加/编辑/删除服务器
- **巡检记录**：历史巡检数据
- **执行巡检**：Web端一键巡检
- **告警管理**：告警查看与处理
- **定时任务**：Cron/间隔定时巡检
- **系统设置**：阈值/通知配置

---

## 第三阶段：定时巡检与告警

### 配置告警通道

通过 Web 界面或 API 配置：

**钉钉机器人：**
```json
{
  "type": "dingtalk",
  "webhook": "https://oapi.dingtalk.com/robot/send?access_token=xxx",
  "secret": "SECxxx"
}
```

**企业微信：**
```json
{
  "type": "wecom",
  "webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
}
```

**邮件：**
```json
{
  "type": "email",
  "smtp_host": "smtp.example.com",
  "smtp_port": 25,
  "smtp_user": "user@example.com",
  "smtp_pass": "password",
  "from_addr": "noreply@example.com",
  "to_addrs": "admin@example.com"
}
```

### 定时任务配置

通过 Web 界面 `/schedule` 添加定时任务：

- **Cron表达式**：`0 9 * * *`（每天9点）
- **间隔执行**：每30分钟

---

## 目录结构

```
inspect/
├── inspect.sh                 # 巡检主脚本
├── run.py                     # Web入口
├── requirements.txt           # Python依赖
├── docker-compose.yml         # Docker编排
├── Dockerfile                 # Docker镜像
├── .env.example               # 环境变量示例
│
├── config/
│   ├── servers.csv           # 服务器清单
│   └── threshold.conf        # 告警阈值配置
│
├── lib/                      # Shell检查模块
│   ├── check_deps.sh         # 依赖检查
│   ├── system_check.sh       # 系统检查
│   ├── cpu_check.sh          # CPU检查
│   ├── memory_check.sh       # 内存检查
│   ├── disk_check.sh         # 磁盘检查
│   ├── network_check.sh      # 网络检查
│   ├── process_check.sh      # 进程检查
│   └── security_check.sh     # 安全检查
│
├── web/                      # Web应用
│   ├── __init__.py           # Flask工厂
│   ├── config.py             # 配置
│   ├── models.py             # 数据模型
│   ├── routes/               # 路由
│   ├── services/             # 服务
│   └── templates/            # 模板
│
├── database/
│   └── init.sql              # 数据库初始化
│
├── docker/
│   └── grafana/              # Grafana配置
│
├── reports/                  # 巡检报告
└── logs/                     # 日志文件
```

---

## 检查模块说明

| 模块 | 检查项 | 告警条件 |
|------|--------|----------|
| system | 主机名、系统版本、内核、运行时间 | 运行时间<1天 |
| cpu | CPU型号、核心数、使用率、负载 | 使用率>80%/95%，负载超阈值 |
| memory | 内存总量、使用率、Swap | 使用率>85%/95%，Swap>50%/80% |
| disk | 磁盘使用率、Inode、IO等待 | 使用率>85%/95% |
| network | 连接数、TIME_WAIT、网关连通性 | 连接数>5000/10000，丢包>5% |
| process | 进程总数、僵尸进程、服务状态 | 僵尸进程>10/50 |
| security | 登录失败、SSH配置、防火墙 | 登录失败>5/10，允许Root登录 |

---

## 阈值配置

编辑 `config/threshold.conf`：

```ini
[cpu]
CPU_USAGE_WARNING=80
CPU_USAGE_CRITICAL=95
LOAD_WARNING_RATIO=1.0
LOAD_CRITICAL_RATIO=1.5

[memory]
MEM_USAGE_WARNING=85
MEM_USAGE_CRITICAL=95
SWAP_USAGE_WARNING=50
SWAP_USAGE_CRITICAL=80

[disk]
DISK_USAGE_WARNING=85
DISK_USAGE_CRITICAL=95

[network]
CONNECTION_WARNING=5000
CONNECTION_CRITICAL=10000

[process]
ZOMBIE_PROCESS_WARNING=10
ZOMBIE_PROCESS_CRITICAL=50

[security]
LOGIN_FAIL_WARNING=5
LOGIN_FAIL_CRITICAL=10
```

---

## API接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/servers` | GET/POST | 服务器列表/创建 |
| `/api/servers/<id>` | GET/PUT/DELETE | 服务器详情/更新/删除 |
| `/api/inspections` | GET | 巡检记录列表 |
| `/api/inspections/run` | POST | 执行巡检 |
| `/api/alerts` | GET | 告警列表 |
| `/api/alerts/<id>/handle` | POST | 处理告警 |
| `/schedule/api/list` | GET | 定时任务列表 |
| `/schedule/api/add` | POST | 添加定时任务 |
| `/settings/api/threshold` | GET/PUT | 阈值设置 |

---

## 常见问题

### 1. SSH连接失败

```bash
# 检查免密登录
ssh root@192.168.1.10 "hostname"

# 检查SSH配置
grep "PermitRootLogin\|PasswordAuthentication" /etc/ssh/sshd_config

# 增加超时时间
./inspect.sh -a -t 60
```

### 2. 依赖工具缺失

脚本会自动检测缺失工具并提供安装建议，也可使用替代方案继续执行。

### 3. 权限问题

```bash
# 确保脚本有执行权限
chmod +x inspect.sh

# 确保目标服务器允许root登录
```

---

## 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.0 | 2026-02-26 | Shell脚本批量巡检 |
| v2.0 | 2026-02-27 | Web管理平台 |
| v3.0 | 2026-02-27 | 定时巡检、告警通知、Grafana |

---

## 许可证

MIT License