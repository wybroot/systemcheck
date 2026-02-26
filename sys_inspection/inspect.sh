#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="${SCRIPT_DIR}/config"
LIB_DIR="${SCRIPT_DIR}/lib"
REPORT_DIR="${SCRIPT_DIR}/reports"
LOG_DIR="${SCRIPT_DIR}/logs"

SERVERS_FILE="${CONFIG_DIR}/servers.csv"
THRESHOLD_FILE="${CONFIG_DIR}/threshold.conf"

mkdir -p "$REPORT_DIR" "$LOG_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

DEPS_USE_ALT=false
DEPS_MISSING=()

SYSTEM_TYPE=""
if [ -f /etc/os-release ]; then
    SYSTEM_TYPE=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
elif [ -f /etc/redhat-release ]; then
    SYSTEM_TYPE="CentOS/RHEL"
fi

load_threshold_config() {
    if [ -f "$THRESHOLD_FILE" ]; then
        source <(grep -v '^#' "$THRESHOLD_FILE" | grep '=' | sed 's/\[/SECTION_/g; s/\]//g')
        
        CPU_USAGE_WARNING=${CPU_USAGE_WARNING:-80}
        CPU_USAGE_CRITICAL=${CPU_USAGE_CRITICAL:-95}
        CPU_LOAD_WARNING_RATIO=${LOAD_WARNING_RATIO:-1.0}
        CPU_LOAD_CRITICAL_RATIO=${LOAD_CRITICAL_RATIO:-1.5}
        
        MEM_USAGE_WARNING=${MEM_USAGE_WARNING:-85}
        MEM_USAGE_CRITICAL=${MEM_USAGE_CRITICAL:-95}
        SWAP_USAGE_WARNING=${SWAP_USAGE_WARNING:-50}
        SWAP_USAGE_CRITICAL=${SWAP_USAGE_CRITICAL:-80}
        
        DISK_USAGE_WARNING=${DISK_USAGE_WARNING:-85}
        DISK_USAGE_CRITICAL=${DISK_USAGE_CRITICAL:-95}
        INODE_USAGE_WARNING=${INODE_USAGE_WARNING:-80}
        INODE_USAGE_CRITICAL=${INODE_USAGE_CRITICAL:-95}
        IO_WAIT_WARNING=${IO_WAIT_WARNING:-50}
        IO_WAIT_CRITICAL=${IO_WAIT_CRITICAL:-80}
        
        CONNECTION_WARNING=${CONNECTION_WARNING:-5000}
        CONNECTION_CRITICAL=${CONNECTION_CRITICAL:-10000}
        TIME_WAIT_WARNING=${TIME_WAIT_WARNING:-3000}
        PACKET_LOSS_WARNING=${PACKET_LOSS_WARNING:-5}
        PACKET_LOSS_CRITICAL=${PACKET_LOSS_CRITICAL:-10}
        
        ZOMBIE_PROCESS_WARNING=${ZOMBIE_PROCESS_WARNING:-10}
        ZOMBIE_PROCESS_CRITICAL=${ZOMBIE_PROCESS_CRITICAL:-50}
        
        LOGIN_FAIL_WARNING=${LOGIN_FAIL_WARNING:-5}
        LOGIN_FAIL_CRITICAL=${LOGIN_FAIL_CRITICAL:-10}
        
        UPTIME_MIN_DAYS=${UPTIME_MIN_DAYS:-1}
    else
        echo "警告: 阈值配置文件不存在，使用默认值"
        set_default_thresholds
    fi
}

set_default_thresholds() {
    CPU_USAGE_WARNING=80
    CPU_USAGE_CRITICAL=95
    CPU_LOAD_WARNING_RATIO=1.0
    CPU_LOAD_CRITICAL_RATIO=1.5
    
    MEM_USAGE_WARNING=85
    MEM_USAGE_CRITICAL=95
    SWAP_USAGE_WARNING=50
    SWAP_USAGE_CRITICAL=80
    
    DISK_USAGE_WARNING=85
    DISK_USAGE_CRITICAL=95
    INODE_USAGE_WARNING=80
    INODE_USAGE_CRITICAL=95
    IO_WAIT_WARNING=50
    IO_WAIT_CRITICAL=80
    
    CONNECTION_WARNING=5000
    CONNECTION_CRITICAL=10000
    TIME_WAIT_WARNING=3000
    PACKET_LOSS_WARNING=5
    PACKET_LOSS_CRITICAL=10
    
    ZOMBIE_PROCESS_WARNING=10
    ZOMBIE_PROCESS_CRITICAL=50
    
    LOGIN_FAIL_WARNING=5
    LOGIN_FAIL_CRITICAL=10
    
    UPTIME_MIN_DAYS=1
}

print_banner() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "          服务器一键巡检系统 v1.0                 "
    echo "=================================================="
    echo -e "${NC}"
}

print_usage() {
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 [选项] [服务器IP]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -a, --all          巡检所有服务器"
    echo "  -f, --file FILE    指定服务器清单文件"
    echo "  -o, --output DIR   指定报告输出目录"
    echo "  -r, --report TYPE  报告类型: text, html, json (默认: html)"
    echo "  -t, --timeout SEC  SSH连接超时时间(默认: 30)"
    echo "  -p, --parallel N   并发执行数量(默认: 10)"
    echo "  -m, --module MOD   只执行指定模块: cpu,mem,disk,net,proc,sec,sys"
    echo "  -e, --email ADDR   发送报告到指定邮箱"
    echo "  -l, --list         列出所有服务器"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 -a                          # 巡检所有服务器"
    echo "  $0 192.168.1.10                # 巡检指定服务器"
    echo "  $0 -m cpu,mem 192.168.1.10     # 只巡检CPU和内存"
    echo "  $0 -a -r html -e admin@xx.com  # 巡检所有并邮件报告"
}

list_servers() {
    echo -e "${BLUE}服务器清单:${NC}"
    echo "------------------------------------------------------------------------"
    printf "%-16s %-20s %-8s %-12s %-12s\n" "IP" "主机名" "端口" "业务" "环境"
    echo "------------------------------------------------------------------------"
    
    if [ -f "$SERVERS_FILE" ]; then
        while IFS=',' read -r ip hostname port user business env services tags; do
            [ "$ip" == "ip" ] && continue
            printf "%-16s %-20s %-8s %-12s %-12s\n" "$ip" "$hostname" "$port" "$business" "$env"
        done < "$SERVERS_FILE"
    else
        echo -e "${RED}错误: 服务器清单文件不存在: $SERVERS_FILE${NC}"
    fi
    echo "------------------------------------------------------------------------"
}

inspect_local() {
    local hostname=$1
    local services=$2
    local modules=$3
    
    local report_data=""
    local overall_status="OK"
    local all_warnings=""
    local all_criticals=""
    
    echo -e "${BLUE}[INFO] 开始巡检本地服务器...${NC}"
    
    if [[ "$modules" == *"sys"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 系统基础检查${NC}"
        source "${LIB_DIR}/system_check.sh"
        check_system
        report_data="${report_data}=== 系统基础信息 ===\n${SYS_RESULT}\n\n"
        if [ "$SYS_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$SYS_STATUS
            [ -n "$SYS_WARNINGS" ] && all_warnings="${all_warnings}${SYS_WARNINGS}; "
            [ -n "$SYS_CRITICALS" ] && all_criticals="${all_criticals}${SYS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"cpu"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> CPU检查${NC}"
        source "${LIB_DIR}/cpu_check.sh"
        check_cpu
        report_data="${report_data}=== CPU检查 ===\n${CPU_RESULT}\n\n"
        if [ "$CPU_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$CPU_STATUS
            [ -n "$CPU_WARNINGS" ] && all_warnings="${all_warnings}${CPU_WARNINGS}; "
            [ -n "$CPU_CRITICALS" ] && all_criticals="${all_criticals}${CPU_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"mem"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 内存检查${NC}"
        source "${LIB_DIR}/memory_check.sh"
        check_memory
        report_data="${report_data}=== 内存检查 ===\n${MEM_RESULT}\n\n"
        if [ "$MEM_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$MEM_STATUS
            [ -n "$MEM_WARNINGS" ] && all_warnings="${all_warnings}${MEM_WARNINGS}; "
            [ -n "$MEM_CRITICALS" ] && all_criticals="${all_criticals}${MEM_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"disk"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 磁盘检查${NC}"
        source "${LIB_DIR}/disk_check.sh"
        check_disk
        report_data="${report_data}=== 磁盘检查 ===\n${DISK_RESULT}\n\n"
        if [ "$DISK_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$DISK_STATUS
            [ -n "$DISK_WARNINGS" ] && all_warnings="${all_warnings}${DISK_WARNINGS}; "
            [ -n "$DISK_CRITICALS" ] && all_criticals="${all_criticals}${DISK_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"net"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 网络检查${NC}"
        source "${LIB_DIR}/network_check.sh"
        check_network
        report_data="${report_data}=== 网络检查 ===\n${NET_RESULT}\n\n"
        if [ "$NET_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$NET_STATUS
            [ -n "$NET_WARNINGS" ] && all_warnings="${all_warnings}${NET_WARNINGS}; "
            [ -n "$NET_CRITICALS" ] && all_criticals="${all_criticals}${NET_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"proc"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 进程与服务检查${NC}"
        export SERVICES="$services"
        source "${LIB_DIR}/process_check.sh"
        check_process
        report_data="${report_data}=== 进程与服务检查 ===\n${PROCESS_RESULT}\n\n"
        if [ "$PROCESS_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$PROCESS_STATUS
            [ -n "$PROCESS_WARNINGS" ] && all_warnings="${all_warnings}${PROCESS_WARNINGS}; "
            [ -n "$PROCESS_CRITICALS" ] && all_criticals="${all_criticals}${PROCESS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"sec"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 安全检查${NC}"
        source "${LIB_DIR}/security_check.sh"
        check_security
        report_data="${report_data}=== 安全检查 ===\n${SEC_RESULT}\n\n"
        if [ "$SEC_STATUS" != "OK" ]; then
            [ "$overall_status" == "OK" ] && overall_status=$SEC_STATUS
            [ -n "$SEC_WARNINGS" ] && all_warnings="${all_warnings}${SEC_WARNINGS}; "
            [ -n "$SEC_CRITICALS" ] && all_criticals="${all_criticals}${SEC_CRITICALS}; "
        fi
    fi
    
    echo ""
    if [ "$overall_status" == "OK" ]; then
        echo -e "${GREEN}[OK] 巡检完成，状态正常${NC}"
    elif [ "$overall_status" == "WARNING" ]; then
        echo -e "${YELLOW}[WARNING] 巡检完成，存在警告项${NC}"
        echo -e "${YELLOW}警告详情: ${all_warnings}${NC}"
    else
        echo -e "${RED}[CRITICAL] 巡检完成，存在严重问题${NC}"
        echo -e "${RED}严重问题: ${all_criticals}${NC}"
        [ -n "$all_warnings" ] && echo -e "${YELLOW}警告: ${all_warnings}${NC}"
    fi
    
    REPORT_DATA="$report_data"
    REPORT_STATUS="$overall_status"
    REPORT_WARNINGS="$all_warnings"
    REPORT_CRITICALS="$all_criticals"
}

inspect_remote() {
    local ip=$1
    local port=${2:-22}
    local user=${3:-root}
    local hostname=$4
    local services=$5
    local modules=$6
    local timeout=${7:-30}
    
    echo -e "${BLUE}[INFO] 开始巡检远程服务器: ${ip} (${hostname})${NC}"
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -o BatchMode=yes"
    
    if ! ssh $ssh_opts -p $port $user@$ip "echo 'SSH连接成功'" 2>/dev/null; then
        echo -e "${RED}[ERROR] SSH连接失败: ${ip}:${port}${NC}"
        return 1
    fi
    
    local remote_script=$(cat << 'REMOTE_EOF'
#!/bin/bash
INSPECT_MODULES="__MODULES__"
INSPECT_SERVICES="__SERVICES__"

CPU_USAGE_WARNING=__CPU_USAGE_WARNING__
CPU_USAGE_CRITICAL=__CPU_USAGE_CRITICAL__
LOAD_WARNING_RATIO=__LOAD_WARNING_RATIO__
LOAD_CRITICAL_RATIO=__LOAD_CRITICAL_RATIO__

MEM_USAGE_WARNING=__MEM_USAGE_WARNING__
MEM_USAGE_CRITICAL=__MEM_USAGE_CRITICAL__
SWAP_USAGE_WARNING=__SWAP_USAGE_WARNING__
SWAP_USAGE_CRITICAL=__SWAP_USAGE_CRITICAL__

DISK_USAGE_WARNING=__DISK_USAGE_WARNING__
DISK_USAGE_CRITICAL=__DISK_USAGE_CRITICAL__
INODE_USAGE_WARNING=__INODE_USAGE_WARNING__
INODE_USAGE_CRITICAL=__INODE_USAGE_CRITICAL__
IO_WAIT_WARNING=__IO_WAIT_WARNING__
IO_WAIT_CRITICAL=__IO_WAIT_CRITICAL__

CONNECTION_WARNING=__CONNECTION_WARNING__
CONNECTION_CRITICAL=__CONNECTION_CRITICAL__
TIME_WAIT_WARNING=__TIME_WAIT_WARNING__
PACKET_LOSS_WARNING=__PACKET_LOSS_WARNING__
PACKET_LOSS_CRITICAL=__PACKET_LOSS_CRITICAL__

ZOMBIE_PROCESS_WARNING=__ZOMBIE_PROCESS_WARNING__
ZOMBIE_PROCESS_CRITICAL=__ZOMBIE_PROCESS_CRITICAL__

LOGIN_FAIL_WARNING=__LOGIN_FAIL_WARNING__
LOGIN_FAIL_CRITICAL=__LOGIN_FAIL_CRITICAL__

UPTIME_MIN_DAYS=__UPTIME_MIN_DAYS__

SERVICES="$INSPECT_SERVICES"

check_system() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    HOSTNAME=$(hostname 2>/dev/null)
    OS_TYPE=""
    OS_VERSION=""
    if [ -f /etc/os-release ]; then
        OS_TYPE=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
        OS_VERSION=$(grep "^VERSION=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="CentOS/RHEL"
        OS_VERSION=$(cat /etc/redhat-release 2>/dev/null)
    fi
    KERNEL_VERSION=$(uname -r 2>/dev/null)
    ARCH=$(uname -m 2>/dev/null)
    SYSTEM_TIME=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    UPTIME_DAYS=0
    if [ -f /proc/uptime ]; then
        UPTIME_SECONDS=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
        UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
    fi
    
    result="主机名: ${HOSTNAME}\n"
    result="${result}操作系统: ${OS_TYPE} ${OS_VERSION}\n"
    result="${result}内核版本: ${KERNEL_VERSION}\n"
    result="${result}系统架构: ${ARCH}\n"
    result="${result}系统时间: ${SYSTEM_TIME}\n"
    result="${result}运行天数: ${UPTIME_DAYS}天"
    
    echo "SYS_STATUS=$status"
    echo "SYS_RESULT=$result"
}

check_cpu() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    if command -v lscpu &>/dev/null; then
        CPU_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    else
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    fi
    
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | sed 's/Model name:\s*//')
    
    if command -v mpstat &>/dev/null; then
        CPU_IDLE=$(mpstat 1 1 | awk '/Average/ {print $NF}')
        CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc)
    else
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        CPU_USAGE=${CPU_USAGE:-0}
    fi
    
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
    LOAD_1MIN=$(echo $LOAD_AVG | awk '{print $1}')
    LOAD_5MIN=$(echo $LOAD_AVG | awk '{print $2}')
    LOAD_15MIN=$(echo $LOAD_AVG | awk '{print $3}')
    
    LOAD_WARNING=$(echo "$CPU_CORES * $LOAD_WARNING_RATIO" | bc 2>/dev/null || echo "$CPU_CORES")
    LOAD_CRITICAL=$(echo "$CPU_CORES * $LOAD_CRITICAL_RATIO" | bc 2>/dev/null || echo "$CPU_CORES")
    
    if (( $(echo "$CPU_USAGE > $CPU_USAGE_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
        status="CRITICAL"
        criticals="CPU使用率 ${CPU_USAGE}% 超过临界阈值"
    elif (( $(echo "$CPU_USAGE > $CPU_USAGE_WARNING" | bc -l 2>/dev/null || echo 0) )); then
        status="WARNING"
        warnings="CPU使用率 ${CPU_USAGE}% 超过警告阈值"
    fi
    
    TOP_CPU_PROCESSES=$(ps -eo pid,user,%cpu,comm --sort=-%cpu | head -n 6 | tail -n 5)
    
    result="CPU型号: ${CPU_MODEL:-未知}\n"
    result="${result}CPU核心数: ${CPU_CORES}\n"
    result="${result}CPU使用率: ${CPU_USAGE}%\n"
    result="${result}系统负载: 1m=${LOAD_1MIN} 5m=${LOAD_5MIN} 15m=${LOAD_15MIN}\n"
    result="${result}TOP5 CPU进程:\n${TOP_CPU_PROCESSES}"
    
    echo "CPU_STATUS=$status"
    echo "CPU_USAGE=$CPU_USAGE"
    echo "CPU_RESULT=$result"
    echo "CPU_WARNINGS=$warnings"
    echo "CPU_CRITICALS=$criticals"
}

check_memory() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    MEM_INFO=$(free -m | grep "Mem:")
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_BUFFERS=$(echo $MEM_INFO | awk '{print $6}')
    MEM_CACHED=$(free -m | grep "Mem:" | awk '{print $7}')
    
    if [ -n "$MEM_BUFFERS" ] && [ -n "$MEM_CACHED" ]; then
        MEM_ACTUAL_USED=$((MEM_USED - MEM_BUFFERS - MEM_CACHED))
        MEM_ACTUAL_USED=$((MEM_ACTUAL_USED < 0 ? 0 : MEM_ACTUAL_USED))
    else
        MEM_ACTUAL_USED=$MEM_USED
    fi
    
    MEM_USAGE=$(echo "scale=2; $MEM_ACTUAL_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo "0")
    
    SWAP_INFO=$(free -m | grep "Swap:")
    SWAP_TOTAL=$(echo $SWAP_INFO | awk '{print $2}')
    SWAP_USED=$(echo $SWAP_INFO | awk '{print $3}')
    
    if [ "$SWAP_TOTAL" -gt 0 ]; then
        SWAP_USAGE=$(echo "scale=2; $SWAP_USED * 100 / $SWAP_TOTAL" | bc 2>/dev/null || echo "0")
    else
        SWAP_USAGE=0
    fi
    
    if (( $(echo "$MEM_USAGE > $MEM_USAGE_CRITICAL" | bc -l 2>/dev/null || echo 0) )); then
        status="CRITICAL"
        criticals="内存使用率 ${MEM_USAGE}% 超过临界阈值"
    elif (( $(echo "$MEM_USAGE > $MEM_USAGE_WARNING" | bc -l 2>/dev/null || echo 0) )); then
        status="WARNING"
        warnings="内存使用率 ${MEM_USAGE}% 超过警告阈值"
    fi
    
    TOP_MEM_PROCESSES=$(ps -eo pid,user,%mem,comm --sort=-%mem | head -n 6 | tail -n 5)
    
    result="内存总量: ${MEM_TOTAL}MB\n"
    result="${result}内存使用: ${MEM_USED}MB\n"
    result="${result}内存使用率: ${MEM_USAGE}%\n"
    result="${result}Swap使用率: ${SWAP_USAGE}%\n"
    result="${result}TOP5 内存进程:\n${TOP_MEM_PROCESSES}"
    
    echo "MEM_STATUS=$status"
    echo "MEM_USAGE=$MEM_USAGE"
    echo "MEM_RESULT=$result"
    echo "MEM_WARNINGS=$warnings"
    echo "MEM_CRITICALS=$criticals"
}

check_disk() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    DISK_INFO=$(df -hP 2>/dev/null | grep -v "Filesystem" | grep -v "tmpfs" | grep -v "devtmpfs")
    
    while IFS= read -r line; do
        local usage=$(echo $line | awk '{print $5}' | tr -d '%')
        local mountpoint=$(echo $line | awk '{print $6}')
        
        if [ "$usage" -gt "$DISK_USAGE_CRITICAL" ] 2>/dev/null; then
            status="CRITICAL"
            criticals="$criticals ${mountpoint}(${usage}%)"
        elif [ "$usage" -gt "$DISK_USAGE_WARNING" ] 2>/dev/null; then
            [ "$status" == "OK" ] && status="WARNING"
            warnings="$warnings ${mountpoint}(${usage}%)"
        fi
    done <<< "$DISK_INFO"
    
    result="$DISK_INFO"
    
    echo "DISK_STATUS=$status"
    echo "DISK_RESULT=$result"
    echo "DISK_WARNINGS=$warnings"
    echo "DISK_CRITICALS=$criticals"
}

check_network() {
    local result=""
    local status="OK"
    
    if command -v ss &>/dev/null; then
        CONNECTION_COUNT=$(ss -s 2>/dev/null | grep "estab" | awk '{print $2}' | head -1)
    elif command -v netstat &>/dev/null; then
        CONNECTION_COUNT=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
    fi
    CONNECTION_COUNT=${CONNECTION_COUNT:-0}
    
    result="网络连接数: ${CONNECTION_COUNT}"
    
    echo "NET_STATUS=$status"
    echo "NET_RESULT=$result"
    echo "CONNECTION_COUNT=$CONNECTION_COUNT"
}

check_process() {
    local result=""
    local status="OK"
    local warnings=""
    
    PROCESS_TOTAL=$(ps aux 2>/dev/null | wc -l)
    ZOMBIE_COUNT=$(ps aux 2>/dev/null | grep -c "<defunct>" || echo 0)
    
    if [ "$ZOMBIE_COUNT" -gt "$ZOMBIE_PROCESS_WARNING" ] 2>/dev/null; then
        status="WARNING"
        warnings="僵尸进程数: ${ZOMBIE_COUNT}"
    fi
    
    result="进程总数: ${PROCESS_TOTAL}\n僵尸进程: ${ZOMBIE_COUNT}"
    
    echo "PROCESS_STATUS=$status"
    echo "PROCESS_RESULT=$result"
    echo "PROCESS_WARNINGS=$warnings"
}

check_security() {
    local result=""
    local status="OK"
    
    LOGIN_FAIL_COUNT=0
    if [ -f /var/log/secure ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/secure 2>/dev/null || echo 0)
    elif [ -f /var/log/auth.log ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
    fi
    
    result="登录失败次数: ${LOGIN_FAIL_COUNT}"
    
    echo "SEC_STATUS=$status"
    echo "SEC_RESULT=$result"
}

echo "===INSPECT_START==="

if [[ "$INSPECT_MODULES" == *"sys"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===SYSTEM==="
    check_system
fi

if [[ "$INSPECT_MODULES" == *"cpu"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===CPU==="
    check_cpu
fi

if [[ "$INSPECT_MODULES" == *"mem"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===MEMORY==="
    check_memory
fi

if [[ "$INSPECT_MODULES" == *"disk"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===DISK==="
    check_disk
fi

if [[ "$INSPECT_MODULES" == *"net"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===NETWORK==="
    check_network
fi

if [[ "$INSPECT_MODULES" == *"proc"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===PROCESS==="
    check_process
fi

if [[ "$INSPECT_MODULES" == *"sec"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===SECURITY==="
    check_security
fi

echo "===INSPECT_END==="
REMOTE_EOF
)
    
    remote_script="${remote_script//__MODULES__/$modules}"
    remote_script="${remote_script//__SERVICES__/$services}"
    remote_script="${remote_script//__CPU_USAGE_WARNING__/$CPU_USAGE_WARNING}"
    remote_script="${remote_script//__CPU_USAGE_CRITICAL__/$CPU_USAGE_CRITICAL}"
    remote_script="${remote_script//__LOAD_WARNING_RATIO__/$CPU_LOAD_WARNING_RATIO}"
    remote_script="${remote_script//__LOAD_CRITICAL_RATIO__/$CPU_LOAD_CRITICAL_RATIO}"
    remote_script="${remote_script//__MEM_USAGE_WARNING__/$MEM_USAGE_WARNING}"
    remote_script="${remote_script//__MEM_USAGE_CRITICAL__/$MEM_USAGE_CRITICAL}"
    remote_script="${remote_script//__SWAP_USAGE_WARNING__/$SWAP_USAGE_WARNING}"
    remote_script="${remote_script//__SWAP_USAGE_CRITICAL__/$SWAP_USAGE_CRITICAL}"
    remote_script="${remote_script//__DISK_USAGE_WARNING__/$DISK_USAGE_WARNING}"
    remote_script="${remote_script//__DISK_USAGE_CRITICAL__/$DISK_USAGE_CRITICAL}"
    remote_script="${remote_script//__INODE_USAGE_WARNING__/$INODE_USAGE_WARNING}"
    remote_script="${remote_script//__INODE_USAGE_CRITICAL__/$INODE_USAGE_CRITICAL}"
    remote_script="${remote_script//__IO_WAIT_WARNING__/$IO_WAIT_WARNING}"
    remote_script="${remote_script//__IO_WAIT_CRITICAL__/$IO_WAIT_CRITICAL}"
    remote_script="${remote_script//__CONNECTION_WARNING__/$CONNECTION_WARNING}"
    remote_script="${remote_script//__CONNECTION_CRITICAL__/$CONNECTION_CRITICAL}"
    remote_script="${remote_script//__TIME_WAIT_WARNING__/$TIME_WAIT_WARNING}"
    remote_script="${remote_script//__PACKET_LOSS_WARNING__/$PACKET_LOSS_WARNING}"
    remote_script="${remote_script//__PACKET_LOSS_CRITICAL__/$PACKET_LOSS_CRITICAL}"
    remote_script="${remote_script//__ZOMBIE_PROCESS_WARNING__/$ZOMBIE_PROCESS_WARNING}"
    remote_script="${remote_script//__ZOMBIE_PROCESS_CRITICAL__/$ZOMBIE_PROCESS_CRITICAL}"
    remote_script="${remote_script//__LOGIN_FAIL_WARNING__/$LOGIN_FAIL_WARNING}"
    remote_script="${remote_script//__LOGIN_FAIL_CRITICAL__/$LOGIN_FAIL_CRITICAL}"
    remote_script="${remote_script//__UPTIME_MIN_DAYS__/$UPTIME_MIN_DAYS}"
    
    local result=$(ssh $ssh_opts -p $port $user@$ip "bash -s" <<< "$remote_script" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] 巡检执行失败: ${ip}${NC}"
        echo "$result"
        return 1
    fi
    
    echo "$result"
}

generate_text_report() {
    local output_file=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    cat > "$output_file" << EOF
================================================================
                    服务器巡检报告
================================================================

生成时间: $timestamp

EOF

    for data in "${REPORT_DATA_ARRAY[@]}"; do
        echo -e "$data" >> "$output_file"
        echo "" >> "$output_file"
        echo "----------------------------------------------------------------" >> "$output_file"
        echo "" >> "$output_file"
    done
    
    echo "" >> "$output_file"
    echo "================================================================" >> "$output_file"
    echo "                      巡检摘要" >> "$output_file"
    echo "================================================================" >> "$output_file"
    echo "" >> "$output_file"
    echo "总服务器数: ${#SERVER_IPS[@]}" >> "$output_file"
    echo "正常: ${OK_COUNT:-0}" >> "$output_file"
    echo "警告: ${WARNING_COUNT:-0}" >> "$output_file"
    echo "严重: ${CRITICAL_COUNT:-0}" >> "$output_file"
    echo "" >> "$output_file"
    echo "报告生成完毕: $output_file" >> "$output_file"
    
    echo -e "${GREEN}文本报告已生成: $output_file${NC}"
}

generate_html_report() {
    local output_file=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local date_str=$(date "+%Y%m%d_%H%M%S")
    
    local status_color="#28a745"
    [ "$OVERALL_STATUS" == "WARNING" ] && status_color="#ffc107"
    [ "$OVERALL_STATUS" == "CRITICAL" ] && status_color="#dc3545"
    
    cat > "$output_file" << 'HTML_HEADER'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>服务器巡检报告</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background: #f5f5f5; color: #333; line-height: 1.6; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .header h1 { font-size: 28px; margin-bottom: 10px; }
        .header .meta { font-size: 14px; opacity: 0.9; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 20px; }
        .summary-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .summary-card .value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .summary-card.ok .value { color: #28a745; }
        .summary-card.warning .value { color: #ffc107; }
        .summary-card.critical .value { color: #dc3545; }
        .summary-card .label { color: #666; font-size: 14px; }
        .server-card { background: white; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }
        .server-header { padding: 15px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #eee; }
        .server-header.ok { border-left: 4px solid #28a745; }
        .server-header.warning { border-left: 4px solid #ffc107; }
        .server-header.critical { border-left: 4px solid #dc3545; }
        .server-header h3 { font-size: 16px; }
        .status-badge { padding: 5px 15px; border-radius: 20px; font-size: 12px; font-weight: bold; }
        .status-badge.ok { background: #d4edda; color: #155724; }
        .status-badge.warning { background: #fff3cd; color: #856404; }
        .status-badge.critical { background: #f8d7da; color: #721c24; }
        .server-body { padding: 20px; }
        .section { margin-bottom: 20px; }
        .section h4 { color: #667eea; margin-bottom: 10px; padding-bottom: 5px; border-bottom: 2px solid #667eea; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 10px; }
        .info-item { padding: 8px 12px; background: #f8f9fa; border-radius: 5px; }
        .info-item .key { color: #666; font-size: 12px; }
        .info-item .value { color: #333; font-weight: 500; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; font-size: 12px; }
        .alert { padding: 10px 15px; border-radius: 5px; margin: 10px 0; }
        .alert.warning { background: #fff3cd; border-left: 4px solid #ffc107; }
        .alert.critical { background: #f8d7da; border-left: 4px solid #dc3545; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>服务器巡检报告</h1>
            <div class="meta">生成时间: TIMESTAMP_PLACEHOLDER</div>
        </div>
        <div class="summary">
            <div class="summary-card">
                <div class="label">总服务器数</div>
                <div class="value">TOTAL_PLACEHOLDER</div>
            </div>
            <div class="summary-card ok">
                <div class="label">正常</div>
                <div class="value">OK_PLACEHOLDER</div>
            </div>
            <div class="summary-card warning">
                <div class="label">警告</div>
                <div class="value">WARNING_PLACEHOLDER</div>
            </div>
            <div class="summary-card critical">
                <div class="label">严重</div>
                <div class="value">CRITICAL_PLACEHOLDER</div>
            </div>
        </div>
HTML_HEADER

    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$output_file"
    sed -i "s/TOTAL_PLACEHOLDER/${#SERVER_IPS[@]}/g" "$output_file"
    sed -i "s/OK_PLACEHOLDER/${OK_COUNT:-0}/g" "$output_file"
    sed -i "s/WARNING_PLACEHOLDER/${WARNING_COUNT:-0}/g" "$output_file"
    sed -i "s/CRITICAL_PLACEHOLDER/${CRITICAL_COUNT:-0}/g" "$output_file"
    
    for i in "${!SERVER_IPS[@]}"; do
        local ip="${SERVER_IPS[$i]}"
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local status="${SERVER_STATUSES[$i]}"
        local data="${SERVER_REPORTS[$i]}"
        local warnings="${SERVER_WARNINGS[$i]}"
        local criticals="${SERVER_CRITICALS[$i]}"
        
        local status_class="ok"
        [ "$status" == "WARNING" ] && status_class="warning"
        [ "$status" == "CRITICAL" ] && status_class="critical"
        
        local status_text="正常"
        [ "$status" == "WARNING" ] && status_text="警告"
        [ "$status" == "CRITICAL" ] && status_text="严重"
        
        cat >> "$output_file" << SERVER_CARD
        <div class="server-card">
            <div class="server-header ${status_class}">
                <h3>${hostname} (${ip})</h3>
                <span class="status-badge ${status_class}">${status_text}</span>
            </div>
            <div class="server-body">
SERVER_CARD

        if [ -n "$criticals" ]; then
            echo "                <div class=\"alert critical\"><strong>严重问题:</strong> ${criticals}</div>" >> "$output_file"
        fi
        
        if [ -n "$warnings" ]; then
            echo "                <div class=\"alert warning\"><strong>警告信息:</strong> ${warnings}</div>" >> "$output_file"
        fi
        
        echo "                <pre>${data}</pre>" >> "$output_file"
        echo "            </div>" >> "$output_file"
        echo "        </div>" >> "$output_file"
    done
    
    cat >> "$output_file" << HTML_FOOTER
        <div class="footer">
            <p>服务器一键巡检系统 v1.0 | 报告生成时间: ${timestamp}</p>
        </div>
    </div>
</body>
</html>
HTML_FOOTER

    echo -e "${GREEN}HTML报告已生成: $output_file${NC}"
}

send_email() {
    local to=$1
    local subject=$2
    local body=$3
    local attachment=$4
    
    if command -v mailx &>/dev/null; then
        if [ -n "$attachment" ]; then
            echo "$body" | mailx -s "$subject" -a "$attachment" "$to"
        else
            echo "$body" | mailx -s "$subject" "$to"
        fi
        echo -e "${GREEN}邮件已发送到: $to${NC}"
    elif command -v mutt &>/dev/null; then
        if [ -n "$attachment" ]; then
            echo "$body" | mutt -s "$subject" -a "$attachment" -- "$to"
        else
            echo "$body" | mutt -s "$subject" "$to"
        fi
        echo -e "${GREEN}邮件已发送到: $to${NC}"
    elif command -v sendmail &>/dev/null; then
        {
            echo "Subject: $subject"
            echo "To: $to"
            echo "Content-Type: text/html; charset=UTF-8"
            echo ""
            cat "$attachment"
        } | sendmail -t
        echo -e "${GREEN}邮件已发送到: $to${NC}"
    else
        echo -e "${YELLOW}警告: 未找到邮件发送工具(mailx/mutt/sendmail)，邮件发送失败${NC}"
        echo -e "${YELLOW}请手动查看报告: $attachment${NC}"
    fi
}

main() {
    local inspect_all=false
    local servers_file="$SERVERS_FILE"
    local output_dir="$REPORT_DIR"
    local report_type="html"
    local timeout=30
    local parallel=10
    local modules=""
    local email=""
    local target_ips=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                inspect_all=true
                shift
                ;;
            -f|--file)
                servers_file="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -r|--report)
                report_type="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -p|--parallel)
                parallel="$2"
                shift 2
                ;;
            -m|--module)
                modules="$2"
                shift 2
                ;;
            -e|--email)
                email="$2"
                shift 2
                ;;
            -l|--list)
                list_servers
                exit 0
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                echo -e "${RED}未知选项: $1${NC}"
                print_usage
                exit 1
                ;;
            *)
                target_ips+=("$1")
                shift
                ;;
        esac
    done
    
    mkdir -p "$output_dir"
    
    load_threshold_config
    
    print_banner
    
    source "${LIB_DIR}/check_deps.sh"
    
    if ! check_deps "interactive"; then
        exit 1
    fi
    
    echo ""
    
    SERVER_IPS=()
    SERVER_HOSTNAMES=()
    SERVER_PORTS=()
    SERVER_USERS=()
    SERVER_SERVICES=()
    SERVER_REPORTS=()
    SERVER_STATUSES=()
    SERVER_WARNINGS=()
    SERVER_CRITICALS=()
    
    if [ "$inspect_all" = true ] || [ ${#target_ips[@]} -eq 0 ]; then
        if [ ! -f "$servers_file" ]; then
            echo -e "${RED}错误: 服务器清单文件不存在: $servers_file${NC}"
            exit 1
        fi
        
        while IFS=',' read -r ip hostname port user business env services tags; do
            [ "$ip" == "ip" ] && continue
            [ -z "$ip" ] && continue
            
            SERVER_IPS+=("$ip")
            SERVER_HOSTNAMES+=("$hostname")
            SERVER_PORTS+=("${port:-22}")
            SERVER_USERS+=("${user:-root}")
            SERVER_SERVICES+=("$services")
        done < "$servers_file"
    else
        for ip in "${target_ips[@]}"; do
            local found=false
            if [ -f "$servers_file" ]; then
                while IFS=',' read -r s_ip s_hostname s_port s_user s_business s_env s_services s_tags; do
                    [ "$s_ip" == "ip" ] && continue
                    if [ "$s_ip" == "$ip" ]; then
                        SERVER_IPS+=("$s_ip")
                        SERVER_HOSTNAMES+=("$s_hostname")
                        SERVER_PORTS+=("${s_port:-22}")
                        SERVER_USERS+=("${s_user:-root}")
                        SERVER_SERVICES+=("$s_services")
                        found=true
                        break
                    fi
                done < "$servers_file"
            fi
            
            if [ "$found" = false ]; then
                SERVER_IPS+=("$ip")
                SERVER_HOSTNAMES+=("$ip")
                SERVER_PORTS+=("22")
                SERVER_USERS+=("root")
                SERVER_SERVICES+=("")
            fi
        done
    fi
    
    if [ ${#SERVER_IPS[@]} -eq 0 ]; then
        echo -e "${RED}错误: 没有要巡检的服务器${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}待巡检服务器数量: ${#SERVER_IPS[@]}${NC}"
    echo -e "${BLUE}巡检模块: ${modules:-全部}${NC}"
    echo -e "${BLUE}报告类型: ${report_type}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    OK_COUNT=0
    WARNING_COUNT=0
    CRITICAL_COUNT=0
    
    for i in "${!SERVER_IPS[@]}"; do
        local ip="${SERVER_IPS[$i]}"
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local port="${SERVER_PORTS[$i]}"
        local user="${SERVER_USERS[$i]}"
        local services="${SERVER_SERVICES[$i]}"
        
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}[$((i+1))/${#SERVER_IPS[@]}] 巡检: ${hostname} (${ip})${NC}"
        echo -e "${CYAN}========================================${NC}"
        
        local result=""
        local status="OK"
        local warnings=""
        local criticals=""
        
        if [[ "$ip" == "127.0.0.1" ]] || [[ "$ip" == "localhost" ]] || [[ "$ip" == "$(hostname -I 2>/dev/null | awk '{print $1}')" ]]; then
            inspect_local "$hostname" "$services" "$modules"
            result="$REPORT_DATA"
            status="$REPORT_STATUS"
            warnings="$REPORT_WARNINGS"
            criticals="$REPORT_CRITICALS"
        else
            result=$(inspect_remote "$ip" "$port" "$user" "$hostname" "$services" "$modules" "$timeout")
            
            if [ $? -eq 0 ]; then
                while IFS= read -r line; do
                    case $line in
                        *=*)
                            eval "$line"
                            ;;
                    esac
                done <<< "$result"
                
                if [ "$CPU_STATUS" == "WARNING" ] || [ "$MEM_STATUS" == "WARNING" ] || [ "$DISK_STATUS" == "WARNING" ] || [ "$NET_STATUS" == "WARNING" ] || [ "$PROCESS_STATUS" == "WARNING" ] || [ "$SEC_STATUS" == "WARNING" ]; then
                    status="WARNING"
                fi
                if [ "$CPU_STATUS" == "CRITICAL" ] || [ "$MEM_STATUS" == "CRITICAL" ] || [ "$DISK_STATUS" == "CRITICAL" ] || [ "$NET_STATUS" == "CRITICAL" ] || [ "$PROCESS_STATUS" == "CRITICAL" ] || [ "$SEC_STATUS" == "CRITICAL" ]; then
                    status="CRITICAL"
                fi
                
                warnings="$CPU_WARNINGS $MEM_WARNINGS $DISK_WARNINGS $NET_WARNINGS $PROCESS_WARNINGS $SEC_WARNINGS"
                criticals="$CPU_CRITICALS $MEM_CRITICALS $DISK_CRITICALS $NET_CRITICALS $PROCESS_CRITICALS $SEC_CRITICALS"
            else
                status="CRITICAL"
                criticals="巡检执行失败"
            fi
        fi
        
        SERVER_REPORTS+=("$result")
        SERVER_STATUSES+=("$status")
        SERVER_WARNINGS+=("$warnings")
        SERVER_CRITICALS+=("$criticals")
        
        case $status in
            OK) 
                echo -e "${GREEN}[OK] ${hostname} 巡检完成，状态正常${NC}"
                ((OK_COUNT++))
                ;;
            WARNING) 
                echo -e "${YELLOW}[WARNING] ${hostname} 巡检完成，存在警告${NC}"
                ((WARNING_COUNT++))
                ;;
            CRITICAL) 
                echo -e "${RED}[CRITICAL] ${hostname} 巡检完成，存在严重问题${NC}"
                ((CRITICAL_COUNT++))
                ;;
        esac
        
        echo ""
    done
    
    OVERALL_STATUS="OK"
    [ $WARNING_COUNT -gt 0 ] && OVERALL_STATUS="WARNING"
    [ $CRITICAL_COUNT -gt 0 ] && OVERALL_STATUS="CRITICAL"
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}           巡检摘要统计${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "总服务器数: ${#SERVER_IPS[@]}"
    echo -e "${GREEN}正常: ${OK_COUNT}${NC}"
    echo -e "${YELLOW}警告: ${WARNING_COUNT}${NC}"
    echo -e "${RED}严重: ${CRITICAL_COUNT}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    local date_str=$(date "+%Y%m%d_%H%M%S")
    local report_file="${output_dir}/inspection_report_${date_str}.${report_type}"
    
    case $report_type in
        text)
            generate_text_report "$report_file"
            ;;
        html)
            generate_html_report "$report_file"
            ;;
        json)
            echo -e "${YELLOW}JSON报告类型暂不支持，使用HTML格式${NC}"
            generate_html_report "$report_file"
            ;;
        *)
            generate_html_report "$report_file"
            ;;
    esac
    
    if [ -n "$email" ]; then
        local subject="服务器巡检报告 - $(date '+%Y-%m-%d %H:%M')"
        local body="请查收附件中的服务器巡检报告。"
        send_email "$email" "$subject" "$body" "$report_file"
    fi
    
    echo ""
    echo -e "${GREEN}巡检完成！${NC}"
    echo -e "报告文件: ${report_file}"
    
    if [ "$OVERALL_STATUS" == "CRITICAL" ]; then
        exit 2
    elif [ "$OVERALL_STATUS" == "WARNING" ]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"