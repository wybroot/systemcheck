# Java应用CPU高占用诊断脚本

## 概述

本脚本用于快速诊断Java应用CPU占用异常问题，自动采集线程堆栈、GC状态、内存信息等关键数据，并生成详细的诊断报告和解决方案建议。

适用于生产环境快速排查CPU飙高问题，无需手动执行多条命令，一键完成全流程诊断。

## 功能特性

- **多模式运行**：支持自动检测、指定PID、交互选择三种模式
- **高CPU线程定位**：自动识别CPU占用最高的线程并关联堆栈信息
- **GC分析**：检测Full GC频率和内存使用情况
- **死锁检测**：自动识别线程死锁问题
- **阻塞线程统计**：统计BLOCKED状态线程数量
- **系统资源监控**：采集CPU、内存、磁盘、IO状态
- **智能诊断**：根据采集数据自动分析问题并给出解决方案
- **报告生成**：生成详细诊断报告，包含堆栈快照文件

## 环境要求

### 操作系统
- Linux（推荐 CentOS 7+、Ubuntu 18.04+、Debian 10+、Rocky Linux 8+）

### 必需工具

脚本需要以下工具才能正常运行：

| 工具 | 类型 | 用途 | 是否必须 |
|------|------|------|----------|
| jstack | JDK工具 | 获取Java线程堆栈 | 必须 |
| jstat | JDK工具 | 查看GC统计信息 | 必须 |
| jmap | JDK工具 | 获取堆内存信息 | 必须 |
| top | 系统工具 | 查看CPU使用率 | 必须 |
| ps | 系统工具 | 进程管理 | 必须 |
| awk | 系统工具 | 文本处理 | 必须 |
| grep | 系统工具 | 文本搜索 | 必须 |
| sed | 系统工具 | 文本处理 | 必须 |
| bc | 系统工具 | 数学计算 | 可选 |
| iostat | 系统工具 | IO统计 | 可选 |

### 权限要求
- 执行用户需要有访问目标Java进程的权限
- 建议使用与Java应用相同的用户执行
- 如需诊断其他用户进程，需使用root权限

## 安装部署

```bash
# 下载脚本
# 方式1：直接创建文件并粘贴内容

# 方式2：如果有git
git clone <repository_url>

# 添加执行权限
chmod +x java_cpu_diagnosis.sh
```

## 使用方法

### 基本语法

```bash
./java_cpu_diagnosis.sh [选项]
```

### 参数说明

| 参数 | 说明 |
|------|------|
| 无参数 | 自动检测模式，自动选择CPU占用最高的Java进程进行分析 |
| -p \<PID\> | 指定PID模式，直接分析指定的进程号 |
| -i | 交互模式，列出所有Java进程供用户选择 |
| --install | 自动安装缺失的系统工具（需要root/sudo权限） |
| -h | 显示帮助信息 |

### 使用示例

#### 场景1：不知道哪个进程有问题，自动排查

```bash
./java_cpu_diagnosis.sh
```

脚本会自动：
1. 查找所有Java进程
2. 选择CPU占用最高的进程
3. 执行完整诊断流程

#### 场景2：已知问题进程PID，快速诊断

```bash
./java_cpu_diagnosis.sh -p 12345
```

直接分析PID为12345的进程，跳过进程选择步骤。

#### 场景3：交互选择要分析的进程

```bash
./java_cpu_diagnosis.sh -i
```

输出示例：
```
========================================
  当前运行的Java进程列表
========================================
[ 1] PID: 12345    CPU: 85.2%  MEM: 12.5%
     命令: java -jar app-service.jar

[ 2] PID: 23456    CPU: 2.1%   MEM: 8.3%
     命令: java -jar config-server.jar

----------------------------------------
请输入要分析的进程编号 [1-2] (输入 a 自动选择最高CPU, q 退出): 
```

输入说明：
- 输入数字：选择对应进程
- 输入 `a`：自动选择CPU最高的进程
- 输入 `q`：退出脚本

## 工具安装指南

### 自动安装功能

脚本支持自动检测并安装缺失的系统工具：

```bash
# 方式1：使用 --install 参数自动安装后运行
./java_cpu_diagnosis.sh --install

# 方式2：运行时交互式安装
./java_cpu_diagnosis.sh
# 如果检测到缺失工具，会询问是否自动安装
```

**自动安装支持的工具：**
- bc（数学计算工具）
- sysstat（包含iostat）
- net-tools（包含netstat）
- lsof（文件句柄查看）

**注意：**
- 自动安装需要sudo/root权限
- JDK工具（jstack、jstat、jmap）需要手动安装JDK

### JDK工具安装

jstack、jstat、jmap 是JDK自带的诊断工具，需要安装JDK并配置环境变量。

#### Ubuntu/Debian

```bash
# 安装OpenJDK 11
sudo apt update
sudo apt install -y openjdk-11-jdk

# 安装OpenJDK 8
sudo apt update
sudo apt install -y openjdk-8-jdk

# 配置环境变量（添加到 ~/.bashrc 或 /etc/profile）
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# 使配置生效
source ~/.bashrc

# 验证安装
java -version
jstack -h
```

#### CentOS/RHEL/Rocky Linux

```bash
# 安装OpenJDK 11
sudo yum install -y java-11-openjdk-devel

# 安装OpenJDK 8
sudo yum install -y java-1.8.0-openjdk-devel

# 配置环境变量（添加到 ~/.bashrc 或 /etc/profile）
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$JAVA_HOME/bin:$PATH

# 使配置生效
source ~/.bashrc

# 验证安装
java -version
jstack -h
```

#### Alpine Linux

```bash
# 安装OpenJDK
apk add openjdk11

# 配置环境变量
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$JAVA_HOME/bin:$PATH

# 验证安装
java -version
```

#### 手动安装Oracle JDK

```bash
# 1. 下载JDK
# 访问 https://www.oracle.com/java/technologies/downloads/

# 2. 解压到目标目录
tar -xzf jdk-11_linux-x64_bin.tar.gz -C /usr/local/

# 3. 配置环境变量
export JAVA_HOME=/usr/local/jdk-11
export PATH=$JAVA_HOME/bin:$PATH

# 4. 添加到启动脚本（永久生效）
echo 'export JAVA_HOME=/usr/local/jdk-11' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# 5. 验证
java -version
jstack -h
```

### 系统工具安装

| 工具 | Ubuntu/Debian | CentOS/RHEL | Alpine |
|------|---------------|-------------|--------|
| bc | `sudo apt install -y bc` | `sudo yum install -y bc` | `apk add bc` |
| sysstat (iostat) | `sudo apt install -y sysstat` | `sudo yum install -y sysstat` | `apk add sysstat` |
| netstat | `sudo apt install -y net-tools` | `sudo yum install -y net-tools` | `apk add net-tools` |
| lsof | `sudo apt install -y lsof` | `sudo yum install -y lsof` | `apk add lsof` |

### 常见问题排查

#### 问题1：找不到jstack/jstat命令

**症状：**
```
[错误] 缺少必要工具: jstack jstat jmap
```

**原因：**
1. 未安装JDK
2. JDK已安装但JAVA_HOME未配置
3. JAVA_HOME/bin未加入PATH

**解决方案：**
```bash
# 检查Java是否安装
java -version

# 检查JAVA_HOME
echo $JAVA_HOME

# 查找JDK安装路径
find /usr -name "jstack" 2>/dev/null

# 如果找到了jstack路径，临时设置PATH
export PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin:$PATH

# 或使用完整路径运行脚本
/usr/lib/jvm/java-11-openjdk-amd64/bin/jstack <pid>
```

#### 问题2：权限不足

**症状：**
```
[错误] 获取堆栈信息失败，可能需要root权限或进程无响应
```

**解决方案：**
```bash
# 使用与Java进程相同的用户运行
sudo -u <java_user> ./java_cpu_diagnosis.sh

# 或使用root权限
sudo ./java_cpu_diagnosis.sh
```

#### 问题3：bc命令不可用

**症状：**
```
[提示] bc命令不可用
```

**影响：** 无法进行CPU阈值比较，但不影响核心诊断功能

**解决方案：**
```bash
# Ubuntu/Debian
sudo apt install -y bc

# CentOS/RHEL
sudo yum install -y bc
```

#### 问题4：Docker容器环境

**场景：** Java应用运行在Docker容器中

**解决方案：**
```bash
# 方式1：进入容器执行
docker exec -it <container_id> /bin/bash
./java_cpu_diagnosis.sh

# 方式2：在宿主机执行（需要容器使用宿主机的JDK工具）
# 注意：这种方式可能无法获取正确的堆栈信息
docker top <container_id>  # 查看容器进程
sudo ./java_cpu_diagnosis.sh -p <pid>

# 方式3：使用arthas（推荐）
docker exec -it <container_id> /bin/bash
curl -O https://arthas.aliyun.com/arthas-boot.jar
java -jar arthas-boot.jar
```

### 验证环境

运行以下命令验证环境是否正确配置：

```bash
# 一键检查脚本
cat << 'EOF' > check_env.sh
#!/bin/bash
echo "=== 环境检查 ==="
echo ""
echo "JDK工具检查:"
for tool in java jstack jstat jmap; do
    if command -v $tool &> /dev/null; then
        echo "  ✓ $tool: $(command -v $tool)"
    else
        echo "  ✗ $tool: 未找到"
    fi
done
echo ""
echo "系统工具检查:"
for tool in top ps awk grep sed bc iostat; do
    if command -v $tool &> /dev/null; then
        echo "  ✓ $tool: $(command -v $tool)"
    else
        echo "  ✗ $tool: 未找到"
    fi
done
echo ""
echo "Java版本:"
java -version 2>&1 | head -1
echo ""
echo "JAVA_HOME: ${JAVA_HOME:-未设置}"
EOF

chmod +x check_env.sh
./check_env.sh
```

## 诊断流程

脚本执行以下诊断步骤：

```
┌─────────────────────────────────────────────────────────┐
│                    诊断流程图                            │
├─────────────────────────────────────────────────────────┤
│  1. 环境检查                                             │
│     └─ 检查jstack、jstat、top等工具是否可用              │
│                                                          │
│  2. 进程选择                                             │
│     └─ 自动检测/指定PID/交互选择                         │
│                                                          │
│  3. 高CPU线程分析                                        │
│     └─ 使用top -H获取线程级CPU使用率                     │
│                                                          │
│  4. 线程堆栈分析                                         │
│     └─ 使用jstack获取堆栈并关联高CPU线程                │
│                                                          │
│  5. GC分析                                               │
│     └─ 使用jstat分析GC频率和内存使用                     │
│                                                          │
│  6. 内存分析                                             │
│     └─ 使用jmap获取堆内存配置和使用情况                  │
│                                                          │
│  7. 系统资源分析                                         │
│     └─ CPU、内存、磁盘、IO状态                           │
│                                                          │
│  8. 问题诊断                                             │
│     └─ 综合分析并给出解决方案建议                        │
│                                                          │
│  9. 生成报告                                             │
│     └─ 输出报告文件和堆栈快照                            │
└─────────────────────────────────────────────────────────┘
```

## 输出文件

脚本执行后会在 `diagnosis_reports/` 目录下生成以下文件：

| 文件 | 说明 |
|------|------|
| diagnosis_report_YYYYMMDD_HHMMSS.txt | 完整诊断报告 |
| jstack_\<PID\>_YYYYMMDD_HHMMSS.txt | 线程堆栈快照 |
| heap_\<PID\>_YYYYMMDD_HHMMSS.txt | 堆内存详情（需要权限） |

## 报告示例

```
========================================
  问题诊断与解决方案
========================================
[发现问题]
  - 目标进程PID: 12345, 当前CPU: 82%
  - 发生Full GC (次数: 3)，可能存在内存问题
  - 发现15个阻塞线程

[解决方案]
  1. 分析高CPU线程堆栈，定位热点代码
  2. 检查是否存在内存泄漏，优化大对象分配
  3. 检查锁竞争问题，优化同步代码块

[通用优化建议]
  1. 使用JProfiler/Arthas进行深入分析
  2. 开启GC日志：-Xlog:gc*:file=gc.log
  3. 配置合适的堆内存参数
  4. 检查是否有无限循环或死循环代码
  5. 检查是否有频繁的对象创建和销毁
  6. 检查数据库连接池、线程池配置
  7. 检查是否有慢SQL导致的CPU升高
  8. 排查定时任务是否在高峰期执行
```

## 常见问题排查

### 问题1：CPU占用高，定位热点代码

**症状**：Java进程CPU占用持续很高

**排查步骤**：
1. 运行脚本诊断
2. 查看"高CPU线程堆栈分析"部分
3. 找到 nid=0xXXX 对应的堆栈
4. 定位到具体代码行号

**示例输出**：
```
线程ID: 125 (nid: 0x7d) CPU: 45.2%
----------------------------------------
"nioEventLoopGroup-3-1" #125 prio=10 os_prio=0 tid=0x00007f8c4012e800 nid=0x7d runnable [0x00007f8b8b5fe000]
   java.lang.Thread.State: RUNNABLE
        at com.example.service.DataProcessor.processLine(DataProcessor.java:156)
        at com.example.service.DataProcessor.process(DataProcessor.java:89)
```

### 问题2：线程死锁

**症状**：应用无响应，但CPU可能不高

**排查**：脚本会自动检测死锁，报告中会显示：
```
[发现问题]
  - 发现死锁!

[解决方案]
  4. 【紧急】解决死锁问题，检查synchronized和Lock使用
```

### 问题3：频繁Full GC

**症状**：CPU间歇性飙升，应用卡顿

**排查**：查看GC分析部分
```
GC汇总信息：
  S0    S1    E     O     M     CCS   YGC   YGCT    FGC   FGCT   GCT
  0.00  0.00  5.23  98.5  95.2  89.1  156   2.345   3    5.678  8.023

[警告] 老年代内存使用率较高: 98.5%
```

### 问题4：线程阻塞

**症状**：吞吐量下降，响应变慢

**排查**：查看线程状态统计
```
[发现问题]
  - 发现32个阻塞线程

[解决方案]
  3. 检查锁竞争问题，优化同步代码块
```

## 高CPU常见原因

| 原因 | 症状 | 解决方案 |
|------|------|----------|
| 死循环 | 单线程CPU 100% | 检查while/for循环条件 |
| 频繁GC | 多线程CPU高，Full GC多 | 调整堆内存，排查内存泄漏 |
| 线程过多 | 大量RUNNABLE线程 | 优化线程池配置 |
| 锁竞争 | BLOCKED线程多 | 优化同步代码，减小锁粒度 |
| 正则回溯 | CPU高，堆栈显示正则匹配 | 优化正则表达式 |
| 序列化/反序列化 | CPU高在大数据处理时 | 使用高效序列化框架 |
| 加密运算 | 安全相关功能CPU高 | 使用更高效算法或硬件加速 |

## 注意事项

1. **执行时机**：建议在CPU高占用的第一时间执行，以便捕获现场
2. **多次采集**：对于偶发问题，建议多次执行脚本采集数据
3. **权限问题**：如遇权限错误，尝试使用与Java进程相同的用户或root执行
4. **容器环境**：在Docker容器中需要进入容器内部执行
5. **JDK版本**：确保jstack、jstat等工具与目标Java进程JDK版本兼容

## 进阶技巧

### 结合Arthas使用

```bash
# 诊断后发现需要深入分析
# 下载并启动Arthas
curl -O https://arthas.aliyun.com/arthas-boot.jar
java -jar arthas-boot.jar

# 在Arthas中分析
dashboard          # 查看面板
thread -n 5        # 显示CPU最高的5个线程
thread <thread-id> # 查看指定线程堆栈
```

### 持续监控

```bash
# 每分钟采集一次，采集10次
for i in {1..10}; do
    echo "=== 第 $i 次采集 ===" 
    ./java_cpu_diagnosis.sh -p 12345
    sleep 60
done
```

### 结合日志分析

```bash
# 同时查看应用日志
tail -f /var/log/app.log | grep -i "error\|exception\|slow"
```

## 脚本配置

可在脚本开头修改以下配置：

```bash
CPU_THRESHOLD=50      # CPU使用率告警阈值
TOP_N_THREADS=10      # 分析的线程数量
REPORT_DIR="./diagnosis_reports"  # 报告输出目录
```

## 问题反馈

如有问题或建议，请联系运维团队或提交Issue。

## 更新日志

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v2.1 | - | 新增工具自动检测和安装功能，增强JDK工具安装指南 |
| v2.0 | - | 增加交互模式、指定PID模式 |
| v1.0 | - | 初始版本，支持自动诊断 |