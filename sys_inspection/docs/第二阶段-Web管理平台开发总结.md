# 第二阶段（Web 管理平台）开发总结与运维手册

> 文档目标：把“第二阶段 Web 平台”讲清楚，方便后续维护、交接、排障、扩展。  
> 对象：后端开发、运维、测试、项目交付同学。

---

## 1. 阶段目标与交付范围

第二阶段的核心目标是把第一阶段 Shell 巡检能力“平台化”：

1. 提供 Web 页面管理服务器资产
2. 支持在页面触发巡检并查看历史结果
3. 统一存储巡检记录、告警、配置
4. 提供可扩展的调度与通知基础能力

本阶段交付重点：
- Flask Web 应用（登录、仪表盘、服务器管理、巡检管理、告警、设置、定时任务）
- REST API 能力（供页面 AJAX 与后续系统对接）
- PostgreSQL 数据持久化
- Redis 缓存加速
- MinIO 报告对象存储能力
- Docker Compose 一键部署方案

---

## 2. 总体架构设计

## 2.1 架构分层

```text
浏览器
  -> Flask 蓝图路由层（web/routes/*.py）
  -> 服务层（web/services/*.py）
  -> 数据层（SQLAlchemy + PostgreSQL）
  -> 外部组件（Redis / MinIO / APScheduler）
```

## 2.2 关键组件

- Web 框架：Flask
- ORM：Flask-SQLAlchemy
- 数据迁移：Flask-Migrate
- 登录鉴权：Flask-Login
- CSRF：Flask-WTF
- 缓存：Redis
- 对象存储：MinIO
- 调度：APScheduler（后台线程）

---

## 3. 代码结构说明（第二阶段重点）

### 3.1 应用初始化

`web/__init__.py`

职责：
- 创建 Flask app，加载配置
- 初始化 db/migrate/login/csrf
- 初始化 Redis 连接与 MinIO 客户端
- 注册蓝图
- 启动并加载调度任务

蓝图注册：
- `auth`：认证与个人资料
- `main`：首页与仪表盘
- `api`：通用 API
- `servers`：服务器页面
- `inspections`：巡检页面
- `schedule`：定时任务页面/API
- `alerts`：告警页面/API
- `settings`：系统设置页面/API

### 3.2 配置文件

`web/config.py`

关键默认项：
- `SQLALCHEMY_DATABASE_URI`：默认 `postgresql://postgres:postgres@localhost:5432/inspect`
- `REDIS_URL`：默认 `redis://localhost:6379/0`
- `MINIO_ENDPOINT`：默认 `localhost:9000`
- `INSPECT_SCRIPT_PATH`：项目根目录 `inspect.sh`
- `INSPECT_TIMEOUT`：300 秒

---

## 4. 功能模块设计与实现

## 4.1 认证模块（auth）

路由：
- `/login` 登录
- `/register` 注册
- `/logout` 退出
- `/profile` 个人资料

实现要点：
- 用户密码哈希存储（Werkzeug）
- 登录保护使用 `@login_required`
- 用户激活状态校验（`is_active`）

## 4.2 仪表盘（main + /api/dashboard）

页面：`/dashboard`

数据来源：`/api/dashboard`
- 总服务器数
- 巡检总次数
- 待处理告警数
- 最近巡检记录
- 按状态统计分布

缓存策略：
- 仪表盘接口优先读取 Redis 缓存
- 缓存 TTL 60 秒

## 4.3 服务器管理（servers + /api/servers）

页面：
- `/servers/` 列表
- `/servers/add` 新增
- `/servers/<id>/edit` 编辑

API：
- `GET /api/servers` 分页/过滤
- `POST /api/servers` 新建
- `GET /api/servers/<id>` 详情
- `PUT /api/servers/<id>` 更新
- `DELETE /api/servers/<id>` 删除

实现要点：
- IP 格式校验
- SSH 端口合法性校验（1-65535）
- 输入内容基础清洗，避免前端注入脏数据

## 4.4 巡检执行与历史（inspections + InspectorService）

页面：
- `/inspections/` 历史列表
- `/inspections/<id>` 详情
- `/inspections/run` 执行页面

API：
- `GET /api/inspections`
- `GET /api/inspections/<id>`
- `POST /api/inspections/run`

核心实现（`web/services/inspector_service.py`）：
1. 根据 server_id 查资产
2. 组装 `inspect.sh` 命令（单机参数）
3. `subprocess.Popen` 调用 Shell 脚本
4. 解析脚本输出为结构化数据
5. 写入 `inspections`、`inspection_items`、`alerts`

安全处理：
- 命令参数做白名单清洗（IP 等字段）
- 非法 server_id、非法 IP 直接拒绝

## 4.5 告警模块（alerts）

页面：`/alerts/`

API：
- `GET /alerts/api/list`
- `GET /alerts/api/<id>`
- `POST /alerts/api/<id>/handle`
- `POST /alerts/api/<id>/ignore`
- `POST /alerts/api/batch/handle`
- `GET /alerts/api/stats`

告警状态流转：
- `PENDING` -> `HANDLED` / `IGNORED`

## 4.6 定时任务模块（schedule + SchedulerService）

页面：`/schedule/`

API：
- `GET /schedule/api/list`
- `POST /schedule/api/add`
- `DELETE /schedule/api/remove/<job_id>`
- `POST /schedule/api/pause/<job_id>`
- `POST /schedule/api/resume/<job_id>`
- `POST /schedule/api/run/<job_id>`

任务类型：
- `cron`（5 段表达式）
- `interval`（分钟）

实现要点：
- APScheduler 后台调度器
- 定时任务配置持久化到 `settings.key=scheduled_jobs`
- 应用启动时自动恢复任务

## 4.7 设置模块（settings）

页面：`/settings/`

API：
- `GET /settings/api/list`
- `GET|PUT /settings/api/threshold`
- `GET|PUT /settings/api/notify`
- `POST /settings/api/notify/test/<channel_type>`
- `POST /settings/api/notify/channel`
- `DELETE /settings/api/notify/channel/<channel_type>`

能力：
- 阈值配置（CPU/内存/磁盘/连接数/僵尸进程等）
- 通知渠道配置与测试（钉钉/企微/邮件/Webhook）

---

## 5. 数据模型设计

模型文件：`web/models.py`

主要实体：
- `User` 用户
- `Server` 服务器资产
- `Inspection` 巡检主记录
- `InspectionItem` 巡检明细项
- `Alert` 告警记录
- `Setting` 系统配置
- `AuditLog` 审计日志

关系摘要：
- `Server 1 - N Inspection`
- `Inspection 1 - N InspectionItem`
- `Server 1 - N Alert`
- `Inspection 1 - N Alert`

---

## 6. 与第一阶段 Shell 的集成方式

Web 平台并不重写巡检逻辑，而是调用 `inspect.sh`：

1. Web 从数据库读取单台服务器连接参数
2. 通过 `subprocess` 执行 `inspect.sh --host ...`
3. 读取 stdout 结果
4. 解析 `KEY=VALUE` 格式片段
5. 落库并生成告警

优点：
- 复用第一阶段成熟能力
- 降低重复开发风险

注意点：
- 输出格式变化会影响解析器
- 建议保持 Shell 输出向后兼容

---

## 7. API 清单（第二阶段）

## 7.1 核心通用 API（`/api/*`）

- 仪表盘：`GET /api/dashboard`
- 服务器：`GET|POST /api/servers`、`GET|PUT|DELETE /api/servers/<id>`
- 巡检：`GET /api/inspections`、`GET /api/inspections/<id>`、`POST /api/inspections/run`
- 告警：`GET /api/alerts`、`POST /api/alerts/<id>/handle`
- 设置：`GET /api/settings`、`GET|PUT /api/settings/<key>`

## 7.2 业务分组 API

- 告警组：`/alerts/api/*`
- 调度组：`/schedule/api/*`
- 设置组：`/settings/api/*`

---

## 8. 部署方案

## 8.1 Docker Compose（推荐）

组件：
- Postgres
- Redis
- MinIO
- Web（Gunicorn）
- Grafana

启动步骤：

```bash
cp .env.example .env
docker-compose up -d
docker-compose ps
```

默认访问：
- Web: `http://localhost:5000`
- MinIO Console: `http://localhost:9001`
- Grafana: `http://localhost:3000`

## 8.2 本地开发运行（可选）

```bash
pip install -r requirements.txt
python run.py
```

---

## 9. 配置项说明（运维重点）

### 9.1 环境变量（摘录）

- `SECRET_KEY`
- `DATABASE_URL`
- `REDIS_URL`
- `MINIO_ENDPOINT`
- `MINIO_ACCESS_KEY`
- `MINIO_SECRET_KEY`
- `MINIO_BUCKET`
- `MINIO_SECURE`
- `LOGIN_DISABLED`

### 9.2 Setting 表关键键位

- 阈值类：`cpu_usage_warning`、`disk_usage_critical` 等
- 系统类：`inspection_timeout`、`report_retention_days`
- 通知类：`notify_channels`
- 调度类：`scheduled_jobs`

---

## 10. 缓存与性能设计

缓存服务：`web/services/redis_service.py`

已实现缓存点：
- 仪表盘缓存（60s）
- 单机信息缓存（默认 300s）
- 巡检详情缓存（默认 600s）

失效策略：
- 服务器增删改后调用 `clear_all_cache()`
- 关键接口读取前优先命中缓存

---

## 11. 安全设计与当前边界

已做：
- 登录校验与会话管理
- CSRF 防护
- 输入长度与字符清洗
- IP/端口等关键字段合法性校验
- Shell 参数基础清洗

边界与建议：
- `ssh_password` 当前为明文字段（建议后续接入加密存储）
- API 未做细粒度 RBAC（建议按角色拆分权限）
- 生产环境需强制 HTTPS 与安全 Cookie 策略检查

---

## 12. 运维排障手册（第二阶段）

## 12.1 Web 启动失败

排查顺序：
1. `docker-compose logs web`
2. 检查 `DATABASE_URL` 是否可连通
3. 检查 `SECRET_KEY` 是否配置
4. 检查 Gunicorn 启动命令是否正常

## 12.2 巡检触发失败

排查顺序：
1. `inspect.sh` 路径是否存在（`INSPECT_SCRIPT_PATH`）
2. Web 进程用户是否有执行权限
3. 目标机 SSH 连通性
4. 查看 stderr 回传信息

## 12.3 调度任务不执行

排查顺序：
1. APScheduler 是否启动（启动日志）
2. 任务是否成功加载（`scheduled_jobs`）
3. 任务表达式是否有效（cron/interval）
4. 任务是否被 pause

## 12.4 通知发不出去

排查顺序：
1. `notify_channels` 配置是否完整
2. 先走“测试通知”接口验证
3. 检查外网出口与证书问题

---

## 13. 测试与验收建议

上线前最小验收集：

1. 登录/注册/修改资料流程
2. 服务器 CRUD + 筛选分页
3. 单机巡检 + 批量巡检
4. 巡检详情/明细/告警生成
5. 告警处理、忽略、批量处理
6. 阈值配置读写
7. 通知渠道配置 + 测试发送
8. 定时任务增删改停启与立即执行

---

## 14. 与第三阶段的衔接点

第二阶段为第三阶段提供：
- 可运营的资产、巡检、告警、配置数据模型
- 定时任务基础能力（APScheduler）
- 通知通道基础能力
- Web 可视化入口

第三阶段重点在此基础上强化：
- 告警通知闭环
- 计划任务稳定性
- 可观测性（Grafana）

---

## 15. 后续优化建议（Web 阶段）

1. **安全强化**
   - SSH 密码加密存储
   - API 权限颗粒化（admin/operator/viewer）
2. **稳定性提升**
   - 巡检任务异步队列化（Celery/RQ）
   - 长任务与 Web 请求彻底解耦
3. **可观测增强**
   - 统一结构化日志
   - API 性能指标与错误率监控
4. **体验优化**
   - 巡检实时进度
   - 历史报告对比视图

---

## 16. 结论

第二阶段已完成“从脚本到平台”的关键跃迁：
- 数据有沉淀
- 流程可视化
- 能联动 Shell 巡检能力
- 已具备向“定时 + 告警闭环 + 运营化”演进的技术基础

