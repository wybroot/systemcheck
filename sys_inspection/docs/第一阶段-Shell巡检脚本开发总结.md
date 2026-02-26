# 第一阶段：Shell巡检脚本开发总结

## 一、开发概述

### 1.1 开发目标
实现基于SSH的服务器批量巡检脚本，无需在目标服务器安装Agent，通过一台控制机即可完成所有服务器的巡检工作。

### 1.2 开发周期
- 开始时间：2026-02-26
- 完成时间：2026-02-26
- 实际工期：1天

### 1.3 交付物

| 文件/目录 | 说明 | 行数 |
|-----------|------|------|
| inspect.sh | 主巡检脚本 | ~1100行 |
| config/servers.csv | 服务器清单配置 | 示例数据 |
| config/threshold.conf | 告警阈值配置 | ~40行 |
| lib/check_deps.sh | 依赖检查模块 | ~200行 |
| lib/cpu_check.sh | CPU检查模块 | ~120行 |
| lib/memory_check.sh | 内存检查模块 | ~100行 |
| lib/disk_check.sh | 磁盘检查模块 | ~130行 |
| lib/network_check.sh | 网络检查模块 | ~140行 |
| lib/process_check.sh | 进程检查模块 | ~100行 |
| lib/security_check.sh | 安全检查模块 | ~120行 |
| lib/system_check.sh | 系统检查模块 | ~90行 |

## 二、技术实现

### 2.1 架构设计

```
┌─────────────────┐
│   控制机         │
│  inspect.sh     │
└────────┬────────┘
         │ SSH
         ▼
┌─────────────────┐
│  目标服务器      │
│  执行巡检脚本    │
│  返回结果       │
└─────────────────┘
```

### 2.2 模块划分

| 模块 | 功能 | 实现方式 |
|------|------|----------|
| 主脚本 | 参数解析、流程控制、报告生成 | Bash |
| 依赖检查 | 检测系统工具、提供安装指引 | Bash |
| 系统检查 | 主机名、OS、内核、时间 | /proc、uname |
| CPU检查 | 使用率、负载、TOP进程 | mpstat、top、/proc/stat |
| 内存检查 | 使用率、Swap、TOP进程 | free、/proc/meminfo |
| 磁盘检查 | 使用率、Inode、IO | df、iostat、find |
| 网络检查 | 连接数、TCP状态、连通性 | ss、netstat、ping |
| 进程检查 | 进程数、僵尸进程、服务状态 | ps、systemctl |
| 安全检查 | 登录失败、防火墙、SSH配置 | last、iptables |

### 2.3 核心功能实现

#### 2.3.1 依赖检查机制

```bash
# 检查必需工具
for cmd in "${!DEPS_REQUIRED[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_required+=("$cmd")
    fi
done

# 交互式选择处理方式
echo "请选择处理方式:"
echo "[1] 显示安装命令"
echo "[2] 使用替代方案"
echo "[3] 显示详细说明"
echo "[4] 忽略并继续"
```

#### 2.3.2 替代方案实现

```bash
# CPU使用率计算 - 有mpstat时
if has_dep "mpstat" && ! use_alt "mpstat"; then
    CPU_USAGE=$(mpstat 1 1 | awk '/Average/ {print 100-$NF}')
# 无mpstat时使用/proc/stat
else
    read cpu user nice system idle < <(head -1 /proc/stat)
    sleep 1
    read cpu2 user2 nice2 system2 idle2 < <(head -1 /proc/stat)
    CPU_USAGE=$((100 * (total_diff - idle_diff) / total_diff))
fi
```

#### 2.3.3 告警阈值判断

```bash
# 使用bc进行浮点比较
if has_dep "bc" && ! use_alt "bc"; then
    if (( $(echo "$CPU_USAGE > $CPU_USAGE_CRITICAL" | bc -l) )); then
        status="CRITICAL"
    fi
# 无bc时使用整数比较
else
    if [ "${CPU_USAGE%.*}" -gt "$CPU_USAGE_CRITICAL" ]; then
        status="CRITICAL"
    fi
fi
```

## 三、遇到的问题与解决方案

### 3.1 依赖工具缺失问题

**问题描述：**
不同Linux发行版默认安装的工具不同，如CentOS默认没有`bc`，Ubuntu可能没有`netstat`。

**解决方案：**
1. 新增`check_deps.sh`依赖检查模块
2. 定义必需工具（ssh、scp）和可选工具
3. 提供交互式选择：安装命令/替代方案/详细说明/忽略
4. 所有检查模块都实现了替代方案

### 3.2 浮点数计算问题

**问题描述：**
Bash原生不支持浮点数计算，CPU使用率、内存使用率等需要浮点运算。

**解决方案：**
1. 优先使用`bc`进行浮点计算
2. 无`bc`时使用`awk`替代
3. 最终方案使用整数比较（截断小数）

### 3.3 远程执行脚本传输问题

**问题描述：**
远程巡检需要将检查逻辑传送到目标服务器执行。

**解决方案：**
在主脚本中内嵌远程脚本，通过SSH的stdin传递：
```bash
ssh $ssh_opts -p $port $user@$ip "bash -s" <<< "$remote_script"
```

### 3.4 不同系统兼容性问题

**问题描述：**
CentOS、Ubuntu、Debian等系统的命令参数、输出格式不同。

**解决方案：**
1. 使用`/proc`文件系统作为主要数据源（跨平台）
2. 对命令输出进行多模式匹配
3. 提供多个备选命令（如ss和netstat）

## 四、使用方式

### 4.1 基本用法

```bash
# 赋予执行权限
chmod +x inspect.sh

# 巡检所有服务器
./inspect.sh -a

# 巡检指定服务器
./inspect.sh 192.168.1.10 192.168.1.20

# 只巡检CPU和内存
./inspect.sh -m cpu,mem 192.168.1.10

# 生成HTML报告并发送邮件
./inspect.sh -a -r html -e admin@example.com

# 列出所有服务器
./inspect.sh -l
```

### 4.2 配置说明

**服务器清单（config/servers.csv）：**
```csv
ip,hostname,ssh_port,ssh_user,business,env,services,tags
192.168.1.10,web-server-01,22,root,电商平台,生产,nginx|mysql,web
```

**告警阈值（config/threshold.conf）：**
```ini
[CPU]
CPU_USAGE_WARNING=80
CPU_USAGE_CRITICAL=95

[MEMORY]
MEM_USAGE_WARNING=85
MEM_USAGE_CRITICAL=95
```

## 五、后续优化方向

### 5.1 功能增强
- [ ] 支持Windows服务器巡检
- [ ] 增加更多检查项（如Docker、K8s）
- [ ] 支持自定义检查脚本
- [ ] 增加巡检结果对比功能

### 5.2 性能优化
- [ ] 并行执行巡检任务
- [ ] 增量巡检（只检查变化的项）
- [ ] 结果缓存机制

### 5.3 用户体验
- [ ] 彩色终端输出
- [ ] 进度条显示
- [ ] 更友好的错误提示
- [ ] 支持配置文件热加载

## 六、经验总结

### 6.1 开发经验
1. **模块化设计**：将各检查项拆分为独立模块，便于维护和扩展
2. **容错设计**：每个功能都有降级方案，确保核心功能可用
3. **配置分离**：阈值和服务器清单独立配置，便于不同环境使用
4. **日志完善**：详细记录执行过程，便于问题排查

### 6.2 注意事项
1. SSH免密登录是前提条件，需提前配置
2. 部分检查项需要root权限
3. 大规模巡检时注意并发控制
4. 报告文件需定期清理

## 七、版本记录

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.0.0 | 2026-02-26 | 初始版本，包含7大检查模块 |
| v1.1.0 | 2026-02-26 | 新增依赖检查模块，支持替代方案 |