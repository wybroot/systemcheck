# 服务器一键巡检系统

一个面向 Linux 运维巡检的项目，支持：
- **Shell 批量巡检**（第一阶段，核心能力）
- **Web 管理平台**（第二阶段）
- **定时巡检与告警通知**（第三阶段）

---

## 1. 项目概览

### 1.1 典型使用场景

在堡垒机/跳板机执行 `inspect.sh`，通过 SSH 巡检多台目标主机，输出 HTML / Text / JSON 报告。

### 1.2 核心能力

- 多主机并发巡检（支持 `-p` 控制并发数）
- 7 大巡检模块：`sys` / `cpu` / `mem` / `disk` / `net` / `proc` / `sec`
- 报告输出：`html` / `text` / `json`
- 依赖工具交互式处理（安装提示、替代方案、忽略、退出）
- 巡检人支持运行时交互输入（`--inspector` 可直接指定）
- 报告头部展示统一元信息：报告时间、脚本版本、巡检目标、脚本编写人、巡检人
- Linux 兼容性增强（CRLF 自动处理，减少 `dos2unix` 依赖）

---

## 2. 目录结构

```text
sys_inspection/
├── inspect.sh                      # Shell 主脚本（巡检入口）
├── config/
│   ├── servers.csv                 # 目标服务器清单
│   └── threshold.conf              # 阈值配置
├── lib/                            # 巡检模块与依赖检测
│   ├── check_deps.sh
│   ├── system_check.sh
│   ├── cpu_check.sh
│   ├── memory_check.sh
│   ├── disk_check.sh
│   ├── network_check.sh
│   ├── process_check.sh
│   └── security_check.sh
├── reports/                        # 巡检报告输出目录
├── logs/                           # 运行日志目录
├── web/                            # Web 端代码
├── docker/                         # Docker 相关配置
├── docs/                           # 项目文档
└── .gitattributes                  # 行尾规范（LF）
```

---

## 3. Shell 巡检快速开始

## 3.1 先决条件

- 控制机可 SSH 到目标机器
- Bash 环境可用
- 建议安装 `sshpass`（密码登录时需要）
- 建议目标机器有基础系统命令（`awk` / `sed` / `df` / `ps` 等）

### 3.2 配置目标主机 `config/servers.csv`

```csv
ip,hostname,ssh_port,ssh_user,ssh_password,business,env,services,tags
192.168.1.10,web-01,22,root,,web,prod,nginx|php-fpm,app
192.168.1.11,db-01,22,root,YourPass123,db,prod,mysql|redis,data
```

字段说明：
- `ip`：目标主机 IP（必填）
- `hostname`：主机别名（可读性展示）
- `ssh_port` / `ssh_user` / `ssh_password`：连接参数（可缺省使用默认值）
- `services`：进程巡检关注的服务名（`|` 分隔）

### 3.3 常用命令

```bash
# 巡检清单中全部主机
./inspect.sh -a

# 巡检指定主机（通过参数）
./inspect.sh 192.168.1.10 192.168.1.11

# 单机直连参数方式
./inspect.sh --host 192.168.1.10 --user root --password 'xxx'

# 指定巡检模块
./inspect.sh -a -m cpu,mem,disk

# 指定报告类型
./inspect.sh -a -r html
./inspect.sh -a -r text
./inspect.sh -a -r json

# 指定巡检人（不指定则运行时交互输入）
./inspect.sh -a --inspector alice
```

---

## 4. inspect.sh 参数说明

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-a, --all` | 巡检清单中的全部主机 | - |
| `-f, --file FILE` | 指定主机清单文件 | `config/servers.csv` |
| `-o, --output DIR` | 报告输出目录 | `reports/` |
| `-r, --report TYPE` | 报告类型：`text/html/json` | `html` |
| `-t, --timeout SEC` | SSH 连接超时秒数 | `30` |
| `-p, --parallel N` | 并发巡检数 | `5` |
| `-m, --module MOD` | 模块过滤：`cpu,mem,disk,net,proc,sec,sys` | 全模块 |
| `-e, --email ADDR` | 报告邮件发送（依赖本机邮件工具） | 空 |
| `--host IP` | 单机巡检（绕过清单） | 空 |
| `--port PORT` | 单机巡检端口 | `22` |
| `--user USER` | 单机巡检用户 | `root` |
| `--password PASS` | 单机巡检密码 | 空 |
| `--inspector NAME` | 指定巡检人 | 交互输入/`whoami` |
| `-l, --list` | 列出主机清单 | - |
| `-v, --verbose` | 详细模式 | 关闭 |
| `-h, --help` | 帮助 | - |

---

## 5. 依赖检查交互说明（第一步）

当脚本检测到依赖缺失时，会进入交互菜单：

- `[1]` 显示安装命令（手动安装后继续）
- `[2]` 使用替代方案继续执行（功能可能受限）
- `[3]` 显示详细说明（包含安装命令和替代方案）
- `[4]` 忽略并继续执行（跳过依赖相关功能）
- `[0]` 退出脚本

这部分逻辑位于：`lib/check_deps.sh`

---

## 6. 巡检模块与阈值

### 6.1 模块概览

- `sys`：主机基础信息、OS、内核、运行时间
- `cpu`：CPU 使用率、负载、核心数
- `mem`：内存使用率、Swap 使用率
- `disk`：磁盘使用率、磁盘详情
- `net`：连接数、监听端口、TIME_WAIT
- `proc`：进程总数、僵尸进程、服务状态
- `sec`：登录失败、登录成功、防火墙、SELinux

### 6.2 阈值配置文件

`config/threshold.conf`

可按业务情况调整 CPU、内存、磁盘、网络、进程、安全等告警阈值。

---

## 7. 报告说明（已做跨格式一致性）

### 7.1 三种格式统一内容

当前 `html` / `text` / `json` 报告均覆盖以下统一信息：

- 顶部元信息
  - 报告时间
  - 脚本版本
  - 巡检目标数量
  - 脚本编写人（固定：`root_objs`）
  - 巡检人（交互输入或 `--inspector` 指定）
- 汇总统计
  - 总数 / 正常 / 警告 / 严重
  - 占比（百分比）
- 每台主机核心信息
  - 状态、告警摘要、严重摘要
  - 系统信息（hostname/os/kernel 等）
  - 核心指标（cpu/mem/swap/连接数/僵尸进程/登录失败）
  - 模块状态（sys/cpu/mem/disk/net/proc/sec）
  - 原始输出（raw）

### 7.2 HTML 报告增强点

- 更现代化卡片样式（渐变头部、模块标签、告警徽标）
- 主机模块内字段顺序固定（跨机器统一）
- 支持原始输出折叠展示，便于追溯

### 7.3 JSON 报告结构

顶层包含：
- `report_time`
- `version`
- `script_author`
- `inspector`
- `summary`
- `servers[]`

`servers[]` 中包含：
- `ip`, `hostname`, `status`, `warnings`, `criticals`
- `system_info`
- `core_metrics`
- `module_status`
- `raw_output`

---

## 8. 近期关键修复（Shell 阶段）

- 修复 `--host` 场景下目标数组被覆盖问题
- 修复状态聚合与展示不一致问题（新增状态归一化）
- 修复 `LOGIN_FAIL_IPS` 解析/展示缺失
- 修复部分命令在 `pipefail` 下的统计异常（避免 `0\n0`）
- 修复 `StrictHostKeyChecking=accept-new` 在老版本 SSH 不兼容问题
- 修复远程脚本中 `local` 使用导致的兼容性问题
- 修复 HTML 不同主机字段顺序不一致问题（固定输出顺序）
- 增强跨平台行尾兼容：脚本自动处理 CRLF 依赖文件

---

## 9. 行尾与跨平台执行规范（重点）

为避免 Linux 上频繁手动执行 `dos2unix`：

- 已通过 `.gitattributes` 约束 Shell 等文件统一 `LF`
- 主脚本引入 `source_lib()`，在 `source` 依赖脚本时自动兼容 CRLF

建议：
- Windows 编辑器启用 `LF`（不是 `CRLF`）
- 提交前可抽检：`git diff --check`

---

## 10. 常见问题排查

### 10.1 SSH 连接失败

1. 手工验证 SSH：
```bash
ssh -p 22 root@192.168.1.10 "echo ok"
```
2. 若使用密码登录，确认 `sshpass` 可用
3. 增大超时：
```bash
./inspect.sh -a -t 60
```

### 10.2 报告里字段为空

- 某些指标依赖目标机命令（例如 `ss`/`netstat`）
- 若缺失会走替代路径，仍可能出现字段为 `-`

### 10.3 依赖缺失怎么选

- 运维环境推荐选 `[1]`，补齐工具后执行
- 临时应急可选 `[2]` 或 `[4]`
- 不确定时先看 `[3]` 详细说明

---

## 11. 退出码语义

| 退出码 | 说明 |
|---|---|
| `0` | 全部正常 |
| `1` | 存在告警 |
| `2` | 存在严重问题 |

---

## 12. 文档索引

建议先看以下文档：

- `docs/第一阶段-Shell巡检脚本开发总结.md`（已更新为维护手册）
- `docs/报告格式一致性说明.md`（HTML/Text/JSON 字段映射）
- `docs/第二阶段-Web管理平台开发总结.md`
- `docs/第三阶段-定时巡检与告警通知开发总结.md`
- `docs/代码审查报告.md`

---

## 13. 版本记录（简）

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0.0 | 2026-02-26 | 第一阶段初版 |
| v2.0.0 | 2026-02-27 | 稳定性与兼容性修复，报告增强，巡检人信息，格式一致性优化 |
