#!/bin/bash

# Java应用CPU高占用智能诊断脚本
# 作者：智能诊断工具
# 功能：自动排查Java应用CPU异常问题并生成报告
# 支持：自动检测 / 指定PID / 交互选择 / 工具自动安装

# 配置
REPORT_DIR="./diagnosis_reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/diagnosis_report_${TIMESTAMP}.txt"
CPU_THRESHOLD=50
TOP_N_THREADS=10
JAVA_PID=""
AUTO_INSTALL=false

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 创建报告目录
mkdir -p "$REPORT_DIR"

# 显示帮助
show_help() {
    echo -e "${CYAN}用法:${NC}"
    echo "  $0                    # 自动检测模式，自动分析高CPU进程"
    echo "  $0 -p <PID>           # 指定PID模式，直接分析指定进程"
    echo "  $0 -i                 # 交互模式，手动选择要分析的进程"
    echo "  $0 --install          # 自动安装缺失的必要工具"
    echo "  $0 -h                 # 显示帮助信息"
    echo ""
    echo -e "${CYAN}示例:${NC}"
    echo "  $0                    # 自动检测并分析"
    echo "  $0 -p 12345           # 分析PID为12345的进程"
    echo "  $0 -i                 # 列出进程并让你选择"
    echo "  $0 --install          # 自动安装缺失工具后运行诊断"
    exit 0
}

# 日志函数
log() {
    echo -e "$1" | tee -a "$REPORT_FILE"
}

log_header() {
    echo -e "\n========== $1 ==========" | tee -a "$REPORT_FILE"
}

log_console() {
    echo -e "$1"
}

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
    else
        OS_ID="unknown"
    fi
    echo "$OS_ID"
}

# 获取包管理器
get_package_manager() {
    local os=$(detect_os)
    case $os in
        ubuntu|debian|linuxmint)
            echo "apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            echo "yum"
            ;;
        alpine)
            echo "apk"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 获取JDK工具的安装建议
get_jdk_install_guide() {
    local os=$(detect_os)
    local pm=$(get_package_manager)
    
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  JDK工具安装指南${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${CYAN}[说明] jstack、jstat、jmap 是JDK自带的工具${NC}"
    echo -e "${CYAN}       需要安装JDK或JRE，并正确配置JAVA_HOME${NC}"
    echo ""
    
    case $pm in
        apt)
            echo -e "${GREEN}[Ubuntu/Debian] 安装命令:${NC}"
            echo ""
            echo "  # 安装OpenJDK 11"
            echo "  sudo apt update"
            echo "  sudo apt install -y openjdk-11-jdk"
            echo ""
            echo "  # 安装OpenJDK 8"
            echo "  sudo apt update"
            echo "  sudo apt install -y openjdk-8-jdk"
            echo ""
            echo "  # 配置环境变量 (添加到 ~/.bashrc 或 /etc/profile)"
            echo "  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
            echo "  export PATH=\$JAVA_HOME/bin:\$PATH"
            echo "  source ~/.bashrc"
            ;;
        yum)
            echo -e "${GREEN}[CentOS/RHEL] 安装命令:${NC}"
            echo ""
            echo "  # 安装OpenJDK 11"
            echo "  sudo yum install -y java-11-openjdk-devel"
            echo ""
            echo "  # 安装OpenJDK 8"
            echo "  sudo yum install -y java-1.8.0-openjdk-devel"
            echo ""
            echo "  # 配置环境变量 (添加到 ~/.bashrc 或 /etc/profile)"
            echo "  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk"
            echo "  export PATH=\$JAVA_HOME/bin:\$PATH"
            echo "  source ~/.bashrc"
            ;;
        apk)
            echo -e "${GREEN}[Alpine] 安装命令:${NC}"
            echo ""
            echo "  apk add openjdk11"
            echo ""
            echo "  # 配置环境变量"
            echo "  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk"
            echo "  export PATH=\$JAVA_HOME/bin:\$PATH"
            ;;
        *)
            echo -e "${YELLOW}[通用安装方法]${NC}"
            echo ""
            echo "  1. 下载JDK: https://www.oracle.com/java/technologies/downloads/"
            echo "  2. 解压到目标目录: tar -xzf jdk-*.tar.gz -C /usr/local/"
            echo "  3. 配置环境变量:"
            echo "     export JAVA_HOME=/usr/local/jdk-11"
            echo "     export PATH=\$JAVA_HOME/bin:\$PATH"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}[验证安装]${NC}"
    echo "  java -version"
    echo "  jstack -h"
    echo ""
}

# 获取系统工具的安装命令
get_system_tool_install_cmd() {
    local tool=$1
    local os=$(detect_os)
    local pm=$(get_package_manager)
    
    case $tool in
        bc)
            case $pm in
                apt) echo "sudo apt install -y bc" ;;
                yum) echo "sudo yum install -y bc" ;;
                apk) echo "apk add bc" ;;
                *) echo "请手动安装 bc 计算器工具" ;;
            esac
            ;;
        iostat|sysstat)
            case $pm in
                apt) echo "sudo apt install -y sysstat" ;;
                yum) echo "sudo yum install -y sysstat" ;;
                apk) echo "apk add sysstat" ;;
                *) echo "请手动安装 sysstat 包" ;;
            esac
            ;;
        netstat|net-tools)
            case $pm in
                apt) echo "sudo apt install -y net-tools" ;;
                yum) echo "sudo yum install -y net-tools" ;;
                apk) echo "apk add net-tools" ;;
                *) echo "请手动安装 net-tools 包" ;;
            esac
            ;;
        lsof)
            case $pm in
                apt) echo "sudo apt install -y lsof" ;;
                yum) echo "sudo yum install -y lsof" ;;
                apk) echo "apk add lsof" ;;
                *) echo "请手动安装 lsof 工具" ;;
            esac
            ;;
        *)
            echo "未知工具: $tool"
            ;;
    esac
}

# 自动安装缺失的系统工具
auto_install_system_tools() {
    local tools=("$@")
    local pm=$(get_package_manager)
    
    if [ "$pm" = "unknown" ]; then
        log_console "${YELLOW}[警告] 无法识别的操作系统，请手动安装缺失工具${NC}"
        return 1
    fi
    
    log_console "${CYAN}[信息] 检测到包管理器: $pm${NC}"
    log_console "${CYAN}[信息] 将尝试自动安装缺失的系统工具...${NC}"
    
    for tool in "${tools[@]}"; do
        local install_cmd=$(get_system_tool_install_cmd "$tool")
        if [ -n "$install_cmd" ]; then
            log_console "${YELLOW}[安装] 正在安装 $tool ...${NC}"
            if eval "$install_cmd" 2>/dev/null; then
                log_console "${GREEN}[成功] $tool 安装完成${NC}"
            else
                log_console "${RED}[失败] $tool 安装失败，请手动执行: $install_cmd${NC}"
            fi
        fi
    done
    
    return 0
}

# 检查必要的工具
check_tools() {
    log_header "环境检查"
    
    local jdk_tools=("jstack" "jstat" "jmap")
    local sys_tools=("top" "awk" "grep" "sed" "ps")
    local optional_tools=("bc" "iostat")
    
    local missing_jdk=()
    local missing_sys=()
    local missing_optional=()
    
    # 检查JDK工具
    for tool in "${jdk_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_jdk+=("$tool")
        fi
    done
    
    # 检查系统工具
    for tool in "${sys_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_sys+=("$tool")
        fi
    done
    
    # 检查可选工具
    for tool in "${optional_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_optional+=("$tool")
        fi
    done
    
    # 输出检查结果
    if [ ${#missing_jdk[@]} -eq 0 ] && [ ${#missing_sys[@]} -eq 0 ]; then
        log "${GREEN}[OK] 所有必要工具已就绪${NC}"
        
        if [ ${#missing_optional[@]} -gt 0 ]; then
            log "${YELLOW}[提示] 可选工具未安装: ${missing_optional[*]} (不影响核心功能)${NC}"
        fi
        
        # 显示JDK信息
        if command -v java &> /dev/null; then
            local java_version=$(java -version 2>&1 | head -1)
            log "${CYAN}[JDK] $java_version${NC}"
        fi
        
        return 0
    fi
    
    # 有缺失工具
    log "${RED}[错误] 检测到缺失的必要工具${NC}"
    echo ""
    
    if [ ${#missing_jdk[@]} -gt 0 ]; then
        log "${YELLOW}缺失的JDK工具: ${missing_jdk[*]}${NC}"
    fi
    
    if [ ${#missing_sys[@]} -gt 0 ]; then
        log "${YELLOW}缺失的系统工具: ${missing_sys[*]}${NC}"
    fi
    
    # 如果指定了自动安装参数
    if [ "$AUTO_INSTALL" = true ]; then
        if [ ${#missing_sys[@]} -gt 0 ]; then
            auto_install_system_tools "${missing_sys[@]}"
        fi
        
        if [ ${#missing_jdk[@]} -gt 0 ]; then
            get_jdk_install_guide
            log_console "${RED}[错误] JDK工具无法自动安装，请参照上述指南手动安装${NC}"
        fi
        
        # 重新检查
        local still_missing=()
        for tool in "${jdk_tools[@]}" "${sys_tools[@]}"; do
            if ! command -v $tool &> /dev/null; then
                still_missing+=("$tool")
            fi
        done
        
        if [ ${#still_missing[@]} -eq 0 ]; then
            log "${GREEN}[OK] 工具安装完成，继续执行诊断...${NC}"
            return 0
        fi
    else
        # 交互式询问是否安装
        echo ""
        log_console -n "${CYAN}是否尝试自动安装缺失的系统工具? [y/N]: ${NC}"
        read -r install_choice
        
        if [[ "$install_choice" =~ ^[yY] ]]; then
            if [ ${#missing_sys[@]} -gt 0 ]; then
                auto_install_system_tools "${missing_sys[@]}"
            fi
            
            # 重新检查系统工具
            local sys_ok=true
            for tool in "${sys_tools[@]}"; do
                if ! command -v $tool &> /dev/null; then
                    sys_ok=false
                    break
                fi
            done
            
            if [ "$sys_ok" = true ] && [ ${#missing_jdk[@]} -eq 0 ]; then
                log "${GREEN}[OK] 系统工具安装完成，继续执行诊断...${NC}"
                return 0
            fi
        fi
        
        # 显示安装指南
        echo ""
        get_jdk_install_guide
        
        if [ ${#missing_sys[@]} -gt 0 ]; then
            echo ""
            log_console "${YELLOW}[系统工具安装命令]${NC}"
            for tool in "${missing_sys[@]}"; do
                local cmd=$(get_system_tool_install_cmd "$tool")
                if [ -n "$cmd" ]; then
                    log_console "  $cmd"
                fi
            done
        fi
    fi
    
    return 1
}

# 初始化报告
init_report() {
    echo "Java应用CPU诊断报告" > "$REPORT_FILE"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "服务器: $(hostname)" >> "$REPORT_FILE"
    echo "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'=' -f2 || echo 'Unknown')" >> "$REPORT_FILE"
    echo "内核版本: $(uname -r)" >> "$REPORT_FILE"
    echo "目标PID: ${JAVA_PID:-自动检测}" >> "$REPORT_FILE"
    if command -v java &> /dev/null; then
        echo "JDK版本: $(java -version 2>&1 | head -1)" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 获取Java进程列表
get_java_processes() {
    local processes=$(ps -ef | grep java | grep -v grep | awk '{printf "%s|%s|%s|%s\n", $2, $3, $4, substr($0, index($0,$8))}')
    echo "$processes"
}

# 显示进程列表供选择
show_process_list() {
    log_console ""
    log_console "${CYAN}========================================${NC}"
    log_console "${CYAN}  当前运行的Java进程列表${NC}"
    log_console "${CYAN}========================================${NC}"
    
    local processes=$(get_java_processes)
    local i=1
    
    if [ -z "$processes" ]; then
        log_console "${RED}[错误] 未发现运行中的Java进程${NC}"
        return 1
    fi
    
    echo "$processes" | while IFS='|' read pid cpu mem cmd; do
        printf "${BLUE}[%2d]${NC} PID: %-8s CPU: %-5s MEM: %-5s\n" $i "$pid" "${cpu}%" "${mem}%"
        printf "     命令: %.80s\n\n" "$cmd"
        i=$((i+1))
    done
    
    return 0
}

# 交互式选择进程
interactive_select() {
    local processes=$(get_java_processes)
    
    if [ -z "$processes" ]; then
        log_console "${RED}[错误] 未发现运行中的Java进程${NC}"
        return 1
    fi
    
    local pid_array=()
    while IFS='|' read -r pid cpu mem cmd; do
        pid_array+=("$pid")
    done <<< "$processes"
    
    local total=${#pid_array[@]}
    
    while true; do
        show_process_list
        log_console "${CYAN}----------------------------------------${NC}"
        log_console -n "${YELLOW}请输入要分析的进程编号 [1-$total] (输入 a 自动选择最高CPU, q 退出): ${NC}"
        read -r choice
        
        case "$choice" in
            [qQ])
                log_console "已退出"
                exit 0
                ;;
            [aA])
                local highest_pid=$(echo "$processes" | sort -t'|' -k2 -rn | head -1 | cut -d'|' -f1)
                JAVA_PID=$highest_pid
                log_console "${GREEN}已自动选择CPU最高的进程: $JAVA_PID${NC}"
                return 0
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
                    JAVA_PID=${pid_array[$((choice-1))]}
                    log_console "${GREEN}已选择进程: $JAVA_PID${NC}"
                    return 0
                else
                    log_console "${RED}无效输入，请重新选择${NC}"
                fi
                ;;
        esac
    done
}

# 查找Java进程（自动模式）
find_java_processes() {
    log_header "Java进程检测"
    
    local processes=$(get_java_processes)
    
    if [ -z "$processes" ]; then
        log "${RED}[错误] 未发现运行中的Java进程${NC}"
        return 1
    fi
    
    log "发现以下Java进程："
    echo "$processes" | while IFS='|' read pid cpu mem cmd; do
        printf "  PID: %-8s CPU: %-5s MEM: %-5s\n" "$pid" "${cpu}%" "${mem}%" | tee -a "$REPORT_FILE"
        printf "       CMD: %.80s\n" "$cmd" | tee -a "$REPORT_FILE"
    done
    echo ""
    
    return 0
}

# 分析CPU使用情况（自动检测高CPU进程）
analyze_cpu_auto() {
    log_header "CPU使用分析"
    
    local highest_cpu_pid=$(ps -eo pid,pcpu,comm | grep java | grep -v grep | sort -k2 -rn | head -1 | awk '{print $1}')
    local highest_cpu=$(ps -eo pid,pcpu,comm | grep java | grep -v grep | sort -k2 -rn | head -1 | awk '{print $2}')
    
    if [ -z "$highest_cpu_pid" ]; then
        log "${RED}[错误] 无法获取Java进程CPU信息${NC}"
        return 1
    fi
    
    JAVA_PID=$highest_cpu_pid
    log "CPU占用最高的Java进程: PID=$JAVA_PID, CPU=${highest_cpu}%"
    
    if [ ! -z "$highest_cpu" ] && [ $(echo "$highest_cpu > $CPU_THRESHOLD" | bc 2>/dev/null || echo 0) -eq 1 ]; then
        log "${YELLOW}[警告] CPU使用率超过阈值 ${CPU_THRESHOLD}%${NC}"
    else
        log "${GREEN}[提示] CPU使用率未超过阈值，但仍将进行分析${NC}"
    fi
    
    return 0
}

# 验证PID
validate_pid() {
    if [ -z "$JAVA_PID" ]; then
        log_console "${RED}[错误] 未指定进程PID${NC}"
        return 1
    fi
    
    if ! ps -p $JAVA_PID > /dev/null 2>&1; then
        log_console "${RED}[错误] 进程 $JAVA_PID 不存在${NC}"
        return 1
    fi
    
    if ! ps -p $JAVA_PID -o comm= | grep -q java; then
        log_console "${YELLOW}[警告] 进程 $JAVA_PID 可能不是Java进程${NC}"
        log_console -n "是否继续分析? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[yY] ]]; then
            return 1
        fi
    fi
    
    log "${GREEN}[OK] 目标进程 PID: $JAVA_PID${NC}"
    return 0
}

# 获取高CPU线程
get_high_cpu_threads() {
    log_header "高CPU线程分析"
    
    if [ -z "$JAVA_PID" ]; then
        log "[跳过] 无进程需要分析"
        return 0
    fi
    
    log "正在分析进程 $JAVA_PID 的线程CPU使用情况..."
    
    local thread_info=$(top -H -b -n 1 -p $JAVA_PID | tail -n +8 | head -n $TOP_N_THREADS)
    
    log "CPU占用最高的${TOP_N_THREADS}个线程："
    echo "$thread_info" | tee -a "$REPORT_FILE"
    
    echo "$thread_info" | awk 'NF>=12 {print $1, $9}' > /tmp/high_cpu_threads.txt
    
    return 0
}

# 获取线程堆栈
get_thread_stack() {
    log_header "线程堆栈分析"
    
    if [ -z "$JAVA_PID" ]; then
        log "[跳过] 无需获取线程堆栈"
        return 0
    fi
    
    local jstack_file="${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt"
    
    log "正在获取Java线程堆栈信息..."
    
    if jstack $JAVA_PID > "$jstack_file" 2>&1; then
        log "${GREEN}[OK] 堆栈信息已保存到: $jstack_file${NC}"
    else
        log "${RED}[错误] 获取堆栈信息失败，可能需要root权限或进程无响应${NC}"
        return 1
    fi
    
    log "\n高CPU线程堆栈分析："
    
    while read tid cpu; do
        if [ -z "$tid" ] || [ -z "$cpu" ]; then
            continue
        fi
        local nid=$(printf "%x" $tid)
        log "\n----------------------------------------"
        log "线程ID: $tid (nid: 0x$nid) CPU: ${cpu}%"
        log "----------------------------------------"
        
        grep -A 30 "nid=0x$nid" "$jstack_file" | head -20 | tee -a "$REPORT_FILE"
    done < /tmp/high_cpu_threads.txt
    
    return 0
}

# GC分析
analyze_gc() {
    log_header "GC情况分析"
    
    if [ -z "$JAVA_PID" ]; then
        log "[跳过] 无需GC分析"
        return 0
    fi
    
    log "GC统计信息："
    jstat -gc $JAVA_PID 2>/dev/null | tee -a "$REPORT_FILE"
    log "\nGC汇总信息："
    jstat -gcutil $JAVA_PID 2>/dev/null | tee -a "$REPORT_FILE"
    
    local gc_info=$(jstat -gcutil $JAVA_PID 2>/dev/null)
    local old_util=$(echo "$gc_info" | tail -1 | awk '{print $3}')
    
    if [ ! -z "$old_util" ] && [ $(echo "$old_util > 80" | bc 2>/dev/null || echo 0) -eq 1 ]; then
        log "${YELLOW}[警告] 老年代内存使用率较高: ${old_util}%${NC}"
    fi
    
    return 0
}

# 内存分析
analyze_memory() {
    log_header "内存使用分析"
    
    if [ -z "$JAVA_PID" ]; then
        log "[跳过] 无需内存分析"
        return 0
    fi
    
    log "Java进程内存信息："
    
    log "\n进程内存详情："
    ps -p $JAVA_PID -o pid,vsz,rss,pmem,comm --no-headers | awk '{printf "  VSZ: %s KB, RSS: %s KB, MEM: %s%%\n", $2, $3, $4}' | tee -a "$REPORT_FILE"
    
    local jmap_file="${REPORT_DIR}/heap_${JAVA_PID}_${TIMESTAMP}.txt"
    
    log "\n正在获取JVM堆内存信息..."
    if jmap -heap $JAVA_PID > "$jmap_file" 2>&1; then
        log "${GREEN}[OK] 堆内存信息已保存到: $jmap_file${NC}"
        grep -A 20 "Heap Configuration:" "$jmap_file" | head -25 | tee -a "$REPORT_FILE"
        grep -A 10 "Heap Usage:" "$jmap_file" | head -15 | tee -a "$REPORT_FILE"
    else
        log "${YELLOW}[提示] 无法获取堆内存详情，可能需要root权限${NC}"
    fi
    
    return 0
}

# 系统资源分析
analyze_system() {
    log_header "系统资源分析"
    
    log "整体CPU使用情况："
    top -b -n 1 | head -5 | tee -a "$REPORT_FILE"
    
    log "\n内存使用情况："
    free -h | tee -a "$REPORT_FILE"
    
    log "\n磁盘使用情况："
    df -h | grep -E '^/dev|^Filesystem' | tee -a "$REPORT_FILE"
    
    log "\nIO情况："
    if command -v iostat &> /dev/null; then
        iostat -x 1 2 2>/dev/null | tail -20 | tee -a "$REPORT_FILE"
    else
        log "[提示] iostat命令不可用，可安装 sysstat 包"
    fi
    
    return 0
}

# 问题诊断与建议
diagnose() {
    log_header "问题诊断与解决方案"
    
    local issues=()
    local solutions=()
    
    if [ ! -z "$JAVA_PID" ]; then
        local current_cpu=$(ps -p $JAVA_PID -o pcpu --no-headers | awk '{print int($1)}')
        issues+=("目标进程PID: $JAVA_PID, 当前CPU: ${current_cpu}%")
        solutions+=("1. 分析高CPU线程堆栈，定位热点代码")
    fi
    
    if [ ! -z "$JAVA_PID" ]; then
        local fgc=$(jstat -gcutil $JAVA_PID 2>/dev/null | tail -1 | awk '{print $8}')
        if [ ! -z "$fgc" ] && [ "$fgc" -gt 0 ]; then
            issues+=("发生Full GC (次数: $fgc)，可能存在内存问题")
            solutions+=("2. 检查是否存在内存泄漏，优化大对象分配")
        fi
    fi
    
    if [ -f "${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt" ]; then
        local blocked=$(grep -c "BLOCKED" "${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt" 2>/dev/null || echo 0)
        if [ "$blocked" -gt 5 ]; then
            issues+=("发现$blocked个阻塞线程")
            solutions+=("3. 检查锁竞争问题，优化同步代码块")
        fi
        
        local deadlocked=$(grep -c "deadlock" "${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt" 2>/dev/null || echo 0)
        if [ "$deadlocked" -gt 0 ]; then
            issues+=("发现死锁!")
            solutions+=("4. 【紧急】解决死锁问题，检查synchronized和Lock使用")
        fi
        
        local runnable=$(grep -c "RUNNABLE" "${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt" 2>/dev/null || echo 0)
        if [ "$runnable" -gt 50 ]; then
            issues+=("RUNNABLE线程数量较多: $runnable")
            solutions+=("5. 检查线程池配置，避免线程过多导致资源竞争")
        fi
    fi
    
    if [ ${#issues[@]} -eq 0 ]; then
        log "${GREEN}[结论] 系统运行正常，未发现明显问题${NC}"
        log "\n可能的原因："
        log "1. CPU使用率已恢复正常，建议持续监控"
        log "2. 用户量小但存在定时任务或后台任务"
        log "3. GC活动导致的瞬时CPU升高"
        log "4. 外部调用（数据库/网络）阻塞导致线程堆积"
    else
        log "${YELLOW}[发现问题]${NC}"
        for issue in "${issues[@]}"; do
            log "  - $issue"
        done
        
        log "\n${GREEN}[解决方案]${NC}"
        for solution in "${solutions[@]}"; do
            log "  $solution"
        done
        
        log "\n${CYAN}[通用优化建议]${NC}"
        log "  1. 使用JProfiler/Arthas进行深入分析"
        log "  2. 开启GC日志：-Xlog:gc*:file=gc.log"
        log "  3. 配置合适的堆内存参数"
        log "  4. 检查是否有无限循环或死循环代码"
        log "  5. 检查是否有频繁的对象创建和销毁"
        log "  6. 检查数据库连接池、线程池配置"
        log "  7. 检查是否有慢SQL导致的CPU升高"
        log "  8. 排查定时任务是否在高峰期执行"
    fi
    
    return 0
}

# 主函数
main() {
    local mode="auto"
    local input_pid=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p)
                mode="pid"
                input_pid="$2"
                shift 2
                ;;
            -i)
                mode="interactive"
                shift
                ;;
            -h)
                show_help
                ;;
            --install)
                AUTO_INSTALL=true
                shift
                ;;
            *)
                echo "未知参数: $1"
                show_help
                ;;
        esac
    done
    
    echo -e "${CYAN}========================================"
    echo "  Java应用CPU诊断工具 v2.1"
    echo "========================================${NC}"
    echo ""
    
    init_report
    
    if ! check_tools; then
        exit 1
    fi
    
    case $mode in
        pid)
            JAVA_PID=$input_pid
            log "模式: 指定PID模式 (PID: $JAVA_PID)"
            if ! validate_pid; then
                exit 1
            fi
            ;;
        interactive)
            log "模式: 交互选择模式"
            if ! interactive_select; then
                exit 1
            fi
            ;;
        auto)
            log "模式: 自动检测模式"
            find_java_processes
            analyze_cpu_auto
            ;;
    esac
    
    echo ""
    log_console "${CYAN}开始分析进程 $JAVA_PID ...${NC}"
    echo ""
    
    get_high_cpu_threads
    get_thread_stack
    analyze_gc
    analyze_memory
    analyze_system
    diagnose
    
    log_header "诊断完成"
    log "报告文件: $REPORT_FILE"
    log "JStack文件: ${REPORT_DIR}/jstack_${JAVA_PID}_${TIMESTAMP}.txt"
    
    echo ""
    echo -e "${GREEN}========================================"
    echo "  诊断完成！"
    echo "========================================${NC}"
    echo -e "报告已保存到: ${YELLOW}$REPORT_FILE${NC}"
}

main "$@"