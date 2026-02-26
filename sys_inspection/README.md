# 服务器一键巡检系统

## 项目概述

服务器一键巡检系统是一个完整的服务器运维巡检解决方案，包含：
- **第一阶段**：Shell脚本批量巡检
- **第二阶段**：Web管理平台 + 数据持久化
- **第三阶段**：定时巡检 + 告警通知 + Grafana可视化

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| Python | 3.11+ | 后端开发语言 |
| Flask | 3.0 | Web框架 |
| PostgreSQL | 18 | 数据库 |
| Redis | 7 | 缓存 |
| MinIO | 20250427 | 文件存储 |
| Grafana | 11.0 | 可视化大盘 |
| APScheduler | 3.10 | 定时任务 |

## 快速部署

### 方式一：Docker Compose（推荐）

```bash
# 克隆项目
cd /opt/inspect

# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```

服务访问地址：
- Web界面：http://localhost:5000
- Grafana：http://localhost:3000 (admin/admin123)
- MinIO控制台：http://localhost:9001 (minioadmin/minioadmin)

### 方式二：手动部署

```bash
# 1. 安装Python依赖
pip install -r requirements.txt

# 2. 初始化数据库
psql -U postgres -f database/init.sql

# 3. 配置环境变量
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/inspect
export REDIS_URL=redis://localhost:6379/0
export MINIO_ENDPOINT=localhost:9000
export MINIO_ACCESS_KEY=minioadmin
export MINIO_SECRET_KEY=minioadmin

# 4. 启动Web服务
gunicorn -w 4 -b 0.0.0.0:5000 "web:create_app()"
```

## 目录结构

```
inspect/
├── inspect.sh                 # 第一阶段巡检脚本
├── run.py                     # Flask应用入口
├── requirements.txt           # Python依赖
├── Dockerfile                 # Docker镜像
├── docker-compose.yml         # Docker编排
├── config/
│   ├── servers.csv           # 服务器清单
│   └── threshold.conf        # 告警阈值
├── lib/                      # Shell检查模块
│   ├── check_deps.sh         # 依赖检查
│   ├── cpu_check.sh          # CPU检查
│   ├── memory_check.sh       # 内存检查
│   ├── disk_check.sh         # 磁盘检查
│   ├── network_check.sh      # 网络检查
│   ├── process_check.sh      # 进程检查
│   ├── security_check.sh     # 安全检查
│   └── system_check.sh       # 系统检查
├── web/                      # Web应用
│   ├── __init__.py           # Flask工厂
│   ├── config.py             # 配置管理
│   ├── models.py             # 数据模型
│   ├── routes/               # 路由模块
│   ├── services/             # 业务服务
│   ├── templates/            # HTML模板
│   └── static/               # 静态资源
├── database/
│   └── init.sql              # 数据库初始化
├── docker/
│   └── grafana/              # Grafana配置
│       ├── provisioning/
│       └── dashboards/
├── reports/                  # 报告存储
└── logs/                     # 日志存储
```

## 功能模块

### 第一阶段：Shell巡检脚本

```bash
# 巡检所有服务器
./inspect.sh -a

# 巡检指定服务器
./inspect.sh 192.168.1.10

# 生成HTML报告并发送邮件
./inspect.sh -a -r html -e admin@example.com
```

### 第二阶段：Web管理平台

- 服务器管理：添加、编辑、删除服务器
- 巡检记录：查看历史巡检数据和趋势
- 报告查看：在线查看巡检报告
- 数据可视化：仪表盘展示关键指标

### 第三阶段：高级功能

- **定时巡检**：支持Cron表达式和间隔执行
- **告警通知**：支持钉钉、企业微信、邮件、Webhook
- **Grafana大盘**：可视化展示服务器状态和趋势

## API接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /api/servers | GET/POST | 服务器列表/创建 |
| /api/servers/:id | GET/PUT/DELETE | 服务器详情/更新/删除 |
| /api/inspections | GET | 巡检记录列表 |
| /api/inspections/:id | GET | 巡检详情 |
| /api/inspections/run | POST | 执行巡检 |
| /api/alerts | GET | 告警列表 |
| /api/alerts/:id/handle | POST | 处理告警 |
| /schedule/api/list | GET | 定时任务列表 |
| /schedule/api/add | POST | 添加定时任务 |
| /settings/api/threshold | GET/PUT | 阈值设置 |
| /settings/api/notify | GET/PUT | 通知设置 |

## 告警配置

### 钉钉机器人

```json
{
  "type": "dingtalk",
  "webhook": "https://oapi.dingtalk.com/robot/send?access_token=xxx",
  "secret": "SECxxx"
}
```

### 企业微信机器人

```json
{
  "type": "wecom",
  "webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
}
```

### 邮件通知

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

## 常见问题

### 1. Docker服务启动失败

```bash
# 检查端口占用
netstat -tlnp | grep -E "5000|5432|6379|9000|3000"

# 查看日志
docker-compose logs web
```

### 2. 数据库连接失败

```bash
# 检查PostgreSQL状态
docker-compose logs postgres

# 手动初始化数据库
docker-compose exec postgres psql -U postgres -f /docker-entrypoint-initdb.d/init.sql
```

### 3. Grafana数据源配置

- 访问 http://localhost:3000
- 登录后自动加载PostgreSQL数据源和仪表盘
- 默认账号：admin / admin123

## 版本历史

### v1.0 (2026-02-26)
- 第一阶段：Shell脚本批量巡检
- 支持7大检查模块
- 支持依赖检查和替代方案

### v2.0 (2026-02-27)
- 第二阶段：Web管理平台
- PostgreSQL + Redis + MinIO
- 服务器管理、巡检记录、报告查看

### v3.0 (2026-02-27)
- 第三阶段：定时巡检 + 告警通知
- APScheduler定时任务
- 钉钉/企微/邮件/Webhook通知
- Grafana可视化大盘

## 作者

运维工程师

## 许可证

内部使用