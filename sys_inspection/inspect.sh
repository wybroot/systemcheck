#!/bin/bash

set -o pipefail

SCRIPT_VERSION="2.0.0"
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

LOG_FILE=""
PARALLEL_PIDS=()
PARALLEL_RESULTS=()
LOCK_FILE="/tmp/inspect_$$.lock"

cleanup() {
    rm -f "$LOCK_FILE" 2>/dev/null
    for pid in "${PARALLEL_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
}
trap cleanup EXIT

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo -e "${timestamp} [${level}] ${message}"
    
    if [ -n "$LOG_FILE" ]; then
        echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    fi
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

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
        while IFS='=' read -r key value; do
            [ -z "$key" ] && continue
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            case "$key" in
                CPU_USAGE_WARNING|CPU_USAGE_CRITICAL|LOAD_WARNING_RATIO|LOAD_CRITICAL_RATIO|\
                MEM_USAGE_WARNING|MEM_USAGE_CRITICAL|SWAP_USAGE_WARNING|SWAP_USAGE_CRITICAL|\
                DISK_USAGE_WARNING|DISK_USAGE_CRITICAL|INODE_USAGE_WARNING|INODE_USAGE_CRITICAL|\
                IO_WAIT_WARNING|IO_WAIT_CRITICAL|\
                CONNECTION_WARNING|CONNECTION_CRITICAL|TIME_WAIT_WARNING|\
                PACKET_LOSS_WARNING|PACKET_LOSS_CRITICAL|\
                ZOMBIE_PROCESS_WARNING|ZOMBIE_PROCESS_CRITICAL|\
                LOGIN_FAIL_WARNING|LOGIN_FAIL_CRITICAL|\
                UPTIME_MIN_DAYS|TIME_DIFF_MAX_SECONDS|\
                REPORT_TITLE|COMPANY_NAME|REPORT_LANGUAGE)
                    eval "$key=\"$value\""
                    ;;
            esac
        done < "$THRESHOLD_FILE"
    else
        log_warn "阈值配置文件不存在: $THRESHOLD_FILE"
    fi
    
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
}

print_banner() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "          服务器一键巡检系统 v${SCRIPT_VERSION}            "
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
    echo "  -p, --parallel N   并发执行数量(默认: 5)"
    echo "  -m, --module MOD   只执行指定模块: cpu,mem,disk,net,proc,sec,sys"
    echo "  -e, --email ADDR   发送报告到指定邮箱"
    echo "  --host IP          指定单个服务器IP"
    echo "  --port PORT        SSH端口(默认: 22)"
    echo "  --user USER        SSH用户(默认: root)"
    echo "  --password PASS    SSH密码(或设置SSH_PASSWORD环境变量)"
    echo "  -l, --list         列出所有服务器"
    echo "  -v, --verbose      详细输出模式"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 -a                          # 巡检所有服务器"
    echo "  $0 192.168.1.10                # 巡检指定服务器"
    echo "  $0 --host 192.168.1.10 --user appuser --password 'xxx'  # 账密登录巡检"
    echo "  $0 -m cpu,mem 192.168.1.10     # 只巡检CPU和内存"
    echo "  $0 -a -p 10 -r json            # 10并发巡检，生成JSON报告"
    echo "  $0 -a -r html -e admin@xx.com  # 巡检所有并邮件报告"
}

list_servers() {
    echo -e "${BLUE}服务器清单:${NC}"
    echo "------------------------------------------------------------------------"
    printf "%-16s %-20s %-8s %-12s %-12s\n" "IP" "主机名" "端口" "业务" "环境"
    echo "------------------------------------------------------------------------"
    
    if [ -f "$SERVERS_FILE" ]; then
        while IFS=',' read -r ip hostname port user business env services tags || [ -n "$ip" ]; do
            [ "$ip" == "ip" ] && continue
            [ -z "$ip" ] && continue
            printf "%-16s %-20s %-8s %-12s %-12s\n" "$ip" "$hostname" "$port" "$business" "$env"
        done < "$SERVERS_FILE"
    else
        echo -e "${RED}错误: 服务器清单文件不存在: $SERVERS_FILE${NC}"
    fi
    echo "------------------------------------------------------------------------"
}

safe_parse_output() {
    local output="$1"
    local -n result_var=$2
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            case "$key" in
                SYS_STATUS|SYS_RESULT|SYS_WARNINGS|SYS_CRITICALS|\
                CPU_STATUS|CPU_CORES|CPU_USAGE|LOAD_1MIN|LOAD_5MIN|LOAD_15MIN|CPU_RESULT|CPU_WARNINGS|CPU_CRITICALS|\
                MEM_STATUS|MEM_USAGE|MEM_USED|MEM_TOTAL|SWAP_USAGE|MEM_RESULT|MEM_WARNINGS|MEM_CRITICALS|\
                DISK_STATUS|DISK_USAGE|DISK_RESULT|DISK_WARNINGS|DISK_CRITICALS|\
                NET_STATUS|CONNECTION_COUNT|NET_RESULT|NET_WARNINGS|NET_CRITICALS|\
                PROCESS_STATUS|ZOMBIE_COUNT|PROCESS_RESULT|PROCESS_WARNINGS|PROCESS_CRITICALS|\
                SEC_STATUS|SEC_RESULT|SEC_WARNINGS|SEC_CRITICALS)
                    result_var["$key"]="$value"
                    ;;
            esac
        fi
    done <<< "$output"
}

get_overall_status() {
    local -n status_arr=$1
    local status="OK"
    
    for key in "${!status_arr[@]}"; do
        if [[ "$key" == *_STATUS ]]; then
            if [[ "${status_arr[$key]}" == "CRITICAL" ]]; then
                status="CRITICAL"
            elif [[ "${status_arr[$key]}" == "WARNING" && "$status" != "CRITICAL" ]]; then
                status="WARNING"
            fi
        fi
    done
    
    echo "$status"
}

collect_warnings() {
    local -n data_arr=$1
    local warnings=""
    
    for key in "${!data_arr[@]}"; do
        if [[ "$key" == *_WARNINGS && -n "${data_arr[$key]}" ]]; then
            warnings="${warnings}${data_arr[$key]}; "
        fi
    done
    
    echo "$warnings"
}

collect_criticals() {
    local -n data_arr=$1
    local criticals=""
    
    for key in "${!data_arr[@]}"; do
        if [[ "$key" == *_CRITICALS && -n "${data_arr[$key]}" ]]; then
            criticals="${criticals}${data_arr[$criticals]}; "
        fi
    done
    
    echo "$criticals"
}

inspect_local() {
    local hostname=$1
    local services=$2
    local modules=$3
    
    declare -A result_data
    local overall_status="OK"
    local all_warnings=""
    local all_criticals=""
    
    log_info "开始巡检本地服务器: $hostname"
    
    if [[ "$modules" == *"sys"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 系统基础检查${NC}"
        if source "${LIB_DIR}/system_check.sh" && check_system; then
            result_data["SYS_STATUS"]="$SYS_STATUS"
            result_data["SYS_RESULT"]="$SYS_RESULT"
            [ -n "$SYS_WARNINGS" ] && all_warnings="${all_warnings}${SYS_WARNINGS}; "
            [ -n "$SYS_CRITICALS" ] && all_criticals="${all_criticals}${SYS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"cpu"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> CPU检查${NC}"
        if source "${LIB_DIR}/cpu_check.sh" && check_cpu; then
            result_data["CPU_STATUS"]="$CPU_STATUS"
            result_data["CPU_CORES"]="$CPU_CORES"
            result_data["CPU_USAGE"]="$CPU_USAGE"
            result_data["LOAD_1MIN"]="$LOAD_1MIN"
            result_data["LOAD_5MIN"]="$LOAD_5MIN"
            result_data["LOAD_15MIN"]="$LOAD_15MIN"
            result_data["CPU_RESULT"]="$CPU_RESULT"
            [ -n "$CPU_WARNINGS" ] && all_warnings="${all_warnings}${CPU_WARNINGS}; "
            [ -n "$CPU_CRITICALS" ] && all_criticals="${all_criticals}${CPU_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"mem"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 内存检查${NC}"
        if source "${LIB_DIR}/memory_check.sh" && check_memory; then
            result_data["MEM_STATUS"]="$MEM_STATUS"
            result_data["MEM_USAGE"]="$MEM_USAGE"
            result_data["MEM_USED"]="$MEM_USED"
            result_data["MEM_TOTAL"]="$MEM_TOTAL"
            result_data["SWAP_USAGE"]="$SWAP_USAGE"
            result_data["MEM_RESULT"]="$MEM_RESULT"
            [ -n "$MEM_WARNINGS" ] && all_warnings="${all_warnings}${MEM_WARNINGS}; "
            [ -n "$MEM_CRITICALS" ] && all_criticals="${all_criticals}${MEM_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"disk"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 磁盘检查${NC}"
        if source "${LIB_DIR}/disk_check.sh" && check_disk; then
            result_data["DISK_STATUS"]="$DISK_STATUS"
            result_data["DISK_USAGE"]="$DISK_USAGE"
            result_data["DISK_RESULT"]="$DISK_RESULT"
            [ -n "$DISK_WARNINGS" ] && all_warnings="${all_warnings}${DISK_WARNINGS}; "
            [ -n "$DISK_CRITICALS" ] && all_criticals="${all_criticals}${DISK_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"net"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 网络检查${NC}"
        if source "${LIB_DIR}/network_check.sh" && check_network; then
            result_data["NET_STATUS"]="$NET_STATUS"
            result_data["CONNECTION_COUNT"]="$CONNECTION_COUNT"
            result_data["NET_RESULT"]="$NET_RESULT"
            [ -n "$NET_WARNINGS" ] && all_warnings="${all_warnings}${NET_WARNINGS}; "
            [ -n "$NET_CRITICALS" ] && all_criticals="${all_criticals}${NET_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"proc"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 进程与服务检查${NC}"
        export SERVICES="$services"
        if source "${LIB_DIR}/process_check.sh" && check_process; then
            result_data["PROCESS_STATUS"]="$PROCESS_STATUS"
            result_data["ZOMBIE_COUNT"]="$ZOMBIE_COUNT"
            result_data["PROCESS_RESULT"]="$PROCESS_RESULT"
            [ -n "$PROCESS_WARNINGS" ] && all_warnings="${all_warnings}${PROCESS_WARNINGS}; "
            [ -n "$PROCESS_CRITICALS" ] && all_criticals="${all_criticals}${PROCESS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"sec"* ]] || [ -z "$modules" ]; then
        echo -e "${CYAN}>>> 安全检查${NC}"
        if source "${LIB_DIR}/security_check.sh" && check_security; then
            result_data["SEC_STATUS"]="$SEC_STATUS"
            result_data["SEC_RESULT"]="$SEC_RESULT"
            [ -n "$SEC_WARNINGS" ] && all_warnings="${all_warnings}${SEC_WARNINGS}; "
            [ -n "$SEC_CRITICALS" ] && all_criticals="${all_criticals}${SEC_CRITICALS}; "
        fi
    fi
    
    overall_status=$(get_overall_status result_data)
    
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
    
    INSPECT_RESULT_STATUS="$overall_status"
    INSPECT_RESULT_WARNINGS="$all_warnings"
    INSPECT_RESULT_CRITICALS="$all_criticals"
    
    for key in "${!result_data[@]}"; do
        eval "INSPECT_RESULT_${key}=\"${result_data[$key]}\""
    done
}

inspect_remote() {
    local ip=$1
    local port=${2:-22}
    local user=${3:-root}
    local password=$4
    local hostname=$5
    local services=$6
    local modules=$7
    local timeout=${8:-30}
    
    log_info "开始巡检远程服务器: ${ip} (${hostname})"
    
    local ssh_opts="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=${timeout} -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
    local ssh_cmd=""
    
    if [ -n "$password" ]; then
        if ! command -v sshpass &>/dev/null; then
            log_error "需要 sshpass 工具进行密码登录，请安装: yum install -y sshpass 或 apt install -y sshpass"
            return 1
        fi
        ssh_cmd="sshpass -p '$password' ssh $ssh_opts -p $port $user@$ip"
        log_info "使用密码登录: $user@$ip:$port"
    else
        ssh_cmd="ssh $ssh_opts -o BatchMode=yes -p $port $user@$ip"
        log_info "使用免密登录: $user@$ip:$port"
    fi
    
    if ! $ssh_cmd "echo 'SSH连接成功'" 2>/dev/null; then
        log_error "SSH连接失败: ${ip}:${port}"
        return 1
    fi
    
    local remote_script=$(cat << 'REMOTE_EOF'
#!/bin/bash
set -o pipefail

INSPECT_MODULES="__MODULES__"

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

SERVICES="__SERVICES__"

echo "===INSPECT_START==="

if [[ "$INSPECT_MODULES" == *"sys"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===SYSTEM==="
    HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    OS_TYPE=""
    OS_VERSION=""
    if [ -f /etc/os-release ]; then
        OS_TYPE=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
        OS_VERSION=$(grep "^VERSION=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="CentOS/RHEL"
        OS_VERSION=$(cat /etc/redhat-release 2>/dev/null)
    fi
    KERNEL_VERSION=$(uname -r 2>/dev/null || echo "unknown")
    ARCH=$(uname -m 2>/dev/null || echo "unknown")
    SYSTEM_TIME=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    UPTIME_DAYS=0
    if [ -f /proc/uptime ]; then
        UPTIME_SECONDS=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
        UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
    fi
    echo "HOSTNAME=$HOSTNAME"
    echo "OS_TYPE=$OS_TYPE"
    echo "OS_VERSION=$OS_VERSION"
    echo "KERNEL_VERSION=$KERNEL_VERSION"
    echo "ARCH=$ARCH"
    echo "SYSTEM_TIME=$SYSTEM_TIME"
    echo "UPTIME_DAYS=$UPTIME_DAYS"
    echo "SYS_STATUS=OK"
fi

if [[ "$INSPECT_MODULES" == *"cpu"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===CPU==="
    CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    
    if [ -f /proc/stat ]; then
        read cpu user nice system idle iowait irq softirq steal < <(head -1 /proc/stat)
        sleep 1
        read cpu2 user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 < <(head -1 /proc/stat)
        total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
        total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
        idle_diff=$((idle2 - idle))
        total_diff=$((total2 - total1))
        if [ $total_diff -gt 0 ]; then
            CPU_USAGE=$(awk "BEGIN {printf \"%.2f\", 100 * ($total_diff - $idle_diff) / $total_diff}")
        else
            CPU_USAGE="0.00"
        fi
    else
        CPU_USAGE="0.00"
    fi
    
    LOAD_AVG=$(cat /proc/loadavg 2>/dev/null || echo "0 0 0")
    LOAD_1MIN=$(echo $LOAD_AVG | awk '{print $1}')
    LOAD_5MIN=$(echo $LOAD_AVG | awk '{print $2}')
    LOAD_15MIN=$(echo $LOAD_AVG | awk '{print $3}')
    
    LOAD_WARNING=$(awk "BEGIN {printf \"%.2f\", $CPU_CORES * $LOAD_WARNING_RATIO}")
    LOAD_CRITICAL=$(awk "BEGIN {printf \"%.2f\", $CPU_CORES * $LOAD_CRITICAL_RATIO}")
    
    CPU_STATUS="OK"
    CPU_WARNINGS=""
    CPU_CRITICALS=""
    
    CPU_USAGE_INT=${CPU_USAGE%.*}
    if [ "$CPU_USAGE_INT" -gt "$CPU_USAGE_CRITICAL" ] 2>/dev/null; then
        CPU_STATUS="CRITICAL"
        CPU_CRITICALS="CPU使用率 ${CPU_USAGE}% 超过临界阈值 ${CPU_USAGE_CRITICAL}%"
    elif [ "$CPU_USAGE_INT" -gt "$CPU_USAGE_WARNING" ] 2>/dev/null; then
        CPU_STATUS="WARNING"
        CPU_WARNINGS="CPU使用率 ${CPU_USAGE}% 超过警告阈值 ${CPU_USAGE_WARNING}%"
    fi
    
    echo "CPU_CORES=$CPU_CORES"
    echo "CPU_USAGE=$CPU_USAGE"
    echo "LOAD_1MIN=$LOAD_1MIN"
    echo "LOAD_5MIN=$LOAD_5MIN"
    echo "LOAD_15MIN=$LOAD_15MIN"
    echo "CPU_STATUS=$CPU_STATUS"
    echo "CPU_WARNINGS=$CPU_WARNINGS"
    echo "CPU_CRITICALS=$CPU_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"mem"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===MEMORY==="
    MEM_INFO=$(free -m 2>/dev/null | grep "Mem:" || echo "Mem: 0 0 0 0 0 0")
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_AVAILABLE=$(echo $MEM_INFO | awk '{print $7}')
    
    if [ -n "$MEM_AVAILABLE" ] && [ "$MEM_AVAILABLE" != "0" ] && [ "$MEM_TOTAL" -gt 0 ] 2>/dev/null; then
        MEM_ACTUAL_USED=$((MEM_TOTAL - MEM_AVAILABLE))
    else
        MEM_ACTUAL_USED=$MEM_USED
    fi
    
    if [ "$MEM_TOTAL" -gt 0 ] 2>/dev/null; then
        MEM_USAGE=$(awk "BEGIN {printf \"%.2f\", $MEM_ACTUAL_USED * 100 / $MEM_TOTAL}")
    else
        MEM_USAGE="0.00"
    fi
    
    SWAP_INFO=$(free -m 2>/dev/null | grep "Swap:" || echo "Swap: 0 0 0")
    SWAP_TOTAL=$(echo $SWAP_INFO | awk '{print $2}')
    SWAP_USED=$(echo $SWAP_INFO | awk '{print $3}')
    
    if [ "$SWAP_TOTAL" -gt 0 ] 2>/dev/null; then
        SWAP_USAGE=$(awk "BEGIN {printf \"%.2f\", $SWAP_USED * 100 / $SWAP_TOTAL}")
    else
        SWAP_USAGE="0.00"
    fi
    
    MEM_STATUS="OK"
    MEM_WARNINGS=""
    MEM_CRITICALS=""
    
    MEM_USAGE_INT=${MEM_USAGE%.*}
    if [ "$MEM_USAGE_INT" -gt "$MEM_USAGE_CRITICAL" ] 2>/dev/null; then
        MEM_STATUS="CRITICAL"
        MEM_CRITICALS="内存使用率 ${MEM_USAGE}% 超过临界阈值 ${MEM_USAGE_CRITICAL}%"
    elif [ "$MEM_USAGE_INT" -gt "$MEM_USAGE_WARNING" ] 2>/dev/null; then
        MEM_STATUS="WARNING"
        MEM_WARNINGS="内存使用率 ${MEM_USAGE}% 超过警告阈值 ${MEM_USAGE_WARNING}%"
    fi
    
    echo "MEM_TOTAL=$MEM_TOTAL"
    echo "MEM_USED=$MEM_USED"
    echo "MEM_USAGE=$MEM_USAGE"
    echo "SWAP_USAGE=$SWAP_USAGE"
    echo "MEM_STATUS=$MEM_STATUS"
    echo "MEM_WARNINGS=$MEM_WARNINGS"
    echo "MEM_CRITICALS=$MEM_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"disk"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===DISK==="
    DISK_STATUS="OK"
    DISK_WARNINGS=""
    DISK_CRITICALS=""
    DISK_MAX_USAGE=0
    
    DISK_INFO=$(df -hP 2>/dev/null | grep -v "Filesystem" | grep -v "tmpfs" | grep -v "devtmpfs" || echo "")
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        usage=$(echo $line | awk '{print $5}' | tr -d '%')
        mountpoint=$(echo $line | awk '{print $6}')
        
        if [ "$usage" -gt "$DISK_MAX_USAGE" ] 2>/dev/null; then
            DISK_MAX_USAGE=$usage
        fi
        
        if [ "$usage" -gt "$DISK_USAGE_CRITICAL" ] 2>/dev/null; then
            DISK_STATUS="CRITICAL"
            DISK_CRITICALS="${DISK_CRITICALS} ${mountpoint}(${usage}%)"
        elif [ "$usage" -gt "$DISK_USAGE_WARNING" ] 2>/dev/null; then
            [ "$DISK_STATUS" == "OK" ] && DISK_STATUS="WARNING"
            DISK_WARNINGS="${DISK_WARNINGS} ${mountpoint}(${usage}%)"
        fi
    done <<< "$DISK_INFO"
    
    echo "DISK_USAGE=$DISK_MAX_USAGE"
    echo "DISK_STATUS=$DISK_STATUS"
    echo "DISK_WARNINGS=$DISK_WARNINGS"
    echo "DISK_CRITICALS=$DISK_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"net"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===NETWORK==="
    CONNECTION_COUNT=0
    
    if command -v ss &>/dev/null; then
        CONNECTION_COUNT=$(ss -s 2>/dev/null | grep -oP "estab \K\d+" | head -1 || echo 0)
    elif command -v netstat &>/dev/null; then
        CONNECTION_COUNT=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
    fi
    
    NET_STATUS="OK"
    NET_WARNINGS=""
    NET_CRITICALS=""
    
    if [ "$CONNECTION_COUNT" -gt "$CONNECTION_CRITICAL" ] 2>/dev/null; then
        NET_STATUS="CRITICAL"
        NET_CRITICALS="网络连接数 ${CONNECTION_COUNT} 超过临界阈值 ${CONNECTION_CRITICAL}"
    elif [ "$CONNECTION_COUNT" -gt "$CONNECTION_WARNING" ] 2>/dev/null; then
        NET_STATUS="WARNING"
        NET_WARNINGS="网络连接数 ${CONNECTION_COUNT} 超过警告阈值 ${CONNECTION_WARNING}"
    fi
    
    echo "CONNECTION_COUNT=$CONNECTION_COUNT"
    echo "NET_STATUS=$NET_STATUS"
    echo "NET_WARNINGS=$NET_WARNINGS"
    echo "NET_CRITICALS=$NET_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"proc"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===PROCESS==="
    PROCESS_TOTAL=$(ps aux 2>/dev/null | wc -l || echo 0)
    ZOMBIE_COUNT=$(ps aux 2>/dev/null | grep -c "<defunct>" || echo 0)
    
    PROCESS_STATUS="OK"
    PROCESS_WARNINGS=""
    PROCESS_CRITICALS=""
    
    if [ "$ZOMBIE_COUNT" -gt "$ZOMBIE_PROCESS_CRITICAL" ] 2>/dev/null; then
        PROCESS_STATUS="CRITICAL"
        PROCESS_CRITICALS="僵尸进程数 ${ZOMBIE_COUNT} 超过临界阈值 ${ZOMBIE_PROCESS_CRITICAL}"
    elif [ "$ZOMBIE_COUNT" -gt "$ZOMBIE_PROCESS_WARNING" ] 2>/dev/null; then
        PROCESS_STATUS="WARNING"
        PROCESS_WARNINGS="僵尸进程数 ${ZOMBIE_COUNT} 超过警告阈值 ${ZOMBIE_PROCESS_WARNING}"
    fi
    
    echo "PROCESS_TOTAL=$PROCESS_TOTAL"
    echo "ZOMBIE_COUNT=$ZOMBIE_COUNT"
    echo "PROCESS_STATUS=$PROCESS_STATUS"
    echo "PROCESS_WARNINGS=$PROCESS_WARNINGS"
    echo "PROCESS_CRITICALS=$PROCESS_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"sec"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===SECURITY==="
    LOGIN_FAIL_COUNT=0
    
    if [ -f /var/log/secure ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/secure 2>/dev/null || echo 0)
    elif [ -f /var/log/auth.log ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
    fi
    
    SEC_STATUS="OK"
    SEC_WARNINGS=""
    SEC_CRITICALS=""
    
    if [ "$LOGIN_FAIL_COUNT" -gt "$LOGIN_FAIL_CRITICAL" ] 2>/dev/null; then
        SEC_STATUS="CRITICAL"
        SEC_CRITICALS="登录失败次数 ${LOGIN_FAIL_COUNT} 超过临界阈值 ${LOGIN_FAIL_CRITICAL}"
    elif [ "$LOGIN_FAIL_COUNT" -gt "$LOGIN_FAIL_WARNING" ] 2>/dev/null; then
        SEC_STATUS="WARNING"
        SEC_WARNINGS="登录失败次数 ${LOGIN_FAIL_COUNT} 超过警告阈值 ${LOGIN_FAIL_WARNING}"
    fi
    
    echo "LOGIN_FAIL_COUNT=$LOGIN_FAIL_COUNT"
    echo "SEC_STATUS=$SEC_STATUS"
    echo "SEC_WARNINGS=$SEC_WARNINGS"
    echo "SEC_CRITICALS=$SEC_CRITICALS"
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
    
    local result
    result=$($ssh_cmd "bash -s" <<< "$remote_script" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "巡检执行失败: ${ip}"
        echo "$result"
        return 1
    fi
    
    echo "$result"
    return 0
}

inspect_single_server() {
    local ip=$1
    local port=$2
    local user=$3
    local password=$4
    local hostname=$5
    local services=$6
    local modules=$7
    local timeout=$8
    local output_file=$9
    
    local status="OK"
    local warnings=""
    local criticals=""
    local result_data=""
    
    if [[ "$ip" == "127.0.0.1" ]] || [[ "$ip" == "localhost" ]] || [[ "$ip" == "$(hostname -I 2>/dev/null | awk '{print $1}')" ]]; then
        inspect_local "$hostname" "$services" "$modules"
        status="$INSPECT_RESULT_STATUS"
        warnings="$INSPECT_RESULT_WARNINGS"
        criticals="$INSPECT_RESULT_CRITICALS"
    else
        local output
        output=$(inspect_remote "$ip" "$port" "$user" "$password" "$hostname" "$services" "$modules" "$timeout")
        local ret=$?
        
        if [ $ret -eq 0 ]; then
            declare -A parsed_data
            safe_parse_output "$output" parsed_data
            status=$(get_overall_status parsed_data)
            warnings=$(collect_warnings parsed_data)
            criticals=$(collect_criticals parsed_data)
            result_data="$output"
        else
            status="CRITICAL"
            criticals="巡检执行失败: $output"
        fi
    fi
    
    if [ -n "$output_file" ]; then
        {
            echo "IP=$ip"
            echo "HOSTNAME=$hostname"
            echo "STATUS=$status"
            echo "WARNINGS=$warnings"
            echo "CRITICALS=$criticals"
            echo "---RAW_OUTPUT---"
            echo "$result_data"
        } > "$output_file"
    fi
    
    echo "${ip}|${hostname}|${status}|${warnings}|${criticals}"
}

generate_text_report() {
    local output_file=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    {
        echo "================================================================"
        echo "                    服务器巡检报告"
        echo "================================================================"
        echo ""
        echo "生成时间: $timestamp"
        echo ""
        
        for i in "${!SERVER_IPS[@]}"; do
            local ip="${SERVER_IPS[$i]}"
            local hostname="${SERVER_HOSTNAMES[$i]}"
            local status="${SERVER_STATUSES[$i]}"
            
            echo "----------------------------------------------------------------"
            echo "服务器: ${hostname} (${ip})"
            echo "状态: ${status}"
            echo "----------------------------------------------------------------"
            
            if [ -n "${SERVER_WARNINGS[$i]}" ]; then
                echo "警告: ${SERVER_WARNINGS[$i]}"
            fi
            if [ -n "${SERVER_CRITICALS[$i]}" ]; then
                echo "严重: ${SERVER_CRITICALS[$i]}"
            fi
            echo ""
        done
        
        echo "================================================================"
        echo "                      巡检摘要"
        echo "================================================================"
        echo ""
        echo "总服务器数: ${#SERVER_IPS[@]}"
        echo "正常: ${OK_COUNT:-0}"
        echo "警告: ${WARNING_COUNT:-0}"
        echo "严重: ${CRITICAL_COUNT:-0}"
    } > "$output_file"
    
    log_info "文本报告已生成: $output_file"
}

generate_html_report() {
    local output_file=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    {
        echo '<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>服务器巡检报告</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background: #f5f5f5; color: #333; line-height: 1.6; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; }
        .header h1 { font-size: 28px; margin-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 20px; }
        .summary-card { background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-card .value { font-size: 36px; font-weight: bold; margin: 10px 0; }
        .summary-card.ok .value { color: #28a745; }
        .summary-card.warning .value { color: #ffc107; }
        .summary-card.critical .value { color: #dc3545; }
        .server-card { background: white; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); overflow: hidden; }
        .server-header { padding: 15px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #eee; }
        .server-header.ok { border-left: 4px solid #28a745; }
        .server-header.warning { border-left: 4px solid #ffc107; }
        .server-header.critical { border-left: 4px solid #dc3545; }
        .status-badge { padding: 5px 15px; border-radius: 20px; font-size: 12px; font-weight: bold; }
        .status-badge.ok { background: #d4edda; color: #155724; }
        .status-badge.warning { background: #fff3cd; color: #856404; }
        .status-badge.critical { background: #f8d7da; color: #721c24; }
        .server-body { padding: 20px; }
        .alert { padding: 10px 15px; border-radius: 5px; margin: 10px 0; }
        .alert.warning { background: #fff3cd; border-left: 4px solid #ffc107; }
        .alert.critical { background: #f8d7da; border-left: 4px solid #dc3545; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>服务器巡检报告</h1>
            <div>生成时间: '"$timestamp"'</div>
        </div>
        <div class="summary">
            <div class="summary-card"><div>总服务器数</div><div class="value">'"${#SERVER_IPS[@]}"'</div></div>
            <div class="summary-card ok"><div>正常</div><div class="value">'"${OK_COUNT:-0}"'</div></div>
            <div class="summary-card warning"><div>警告</div><div class="value">'"${WARNING_COUNT:-0}"'</div></div>
            <div class="summary-card critical"><div>严重</div><div class="value">'"${CRITICAL_COUNT:-0}"'</div></div>
        </div>'
        
        for i in "${!SERVER_IPS[@]}"; do
            local ip="${SERVER_IPS[$i]}"
            local hostname="${SERVER_HOSTNAMES[$i]}"
            local status="${SERVER_STATUSES[$i]}"
            local warnings="${SERVER_WARNINGS[$i]}"
            local criticals="${SERVER_CRITICALS[$i]}"
            
            local status_class="ok"
            [ "$status" == "WARNING" ] && status_class="warning"
            [ "$status" == "CRITICAL" ] && status_class="critical"
            
            local status_text="正常"
            [ "$status" == "WARNING" ] && status_text="警告"
            [ "$status" == "CRITICAL" ] && status_text="严重"
            
            echo '<div class="server-card">'
            echo '<div class="server-header '"$status_class"'">'
            echo "<h3>${hostname} (${ip})</h3>"
            echo '<span class="status-badge '"$status_class"'"'"'>'"$status_text"'</span>'
            echo '</div><div class="server-body">'
            
            [ -n "$criticals" ] && echo "<div class=\"alert critical\"><strong>严重问题:</strong> ${criticals}</div>"
            [ -n "$warnings" ] && echo "<div class=\"alert warning\"><strong>警告信息:</strong> ${warnings}</div>"
            
            echo '</div></div>'
        done
        
        echo '<div style="text-align:center;padding:20px;color:#666;font-size:12px;">'
        echo "服务器一键巡检系统 v${SCRIPT_VERSION} | 报告生成时间: $timestamp"
        echo '</div></div></body></html>'
    } > "$output_file"
    
    log_info "HTML报告已生成: $output_file"
}

generate_json_report() {
    local output_file=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    {
        echo '{'
        echo '  "report_time": "'"$timestamp"'",'
        echo '  "version": "'"${SCRIPT_VERSION}"'",'
        echo '  "summary": {'
        echo '    "total": '"${#SERVER_IPS[@]}"','
        echo '    "ok": '"${OK_COUNT:-0}"','
        echo '    "warning": '"${WARNING_COUNT:-0}"','
        echo '    "critical": '"${CRITICAL_COUNT:-0}"
        echo '  },'
        echo '  "servers": ['
        
        local first=true
        for i in "${!SERVER_IPS[@]}"; do
            local ip="${SERVER_IPS[$i]}"
            local hostname="${SERVER_HOSTNAMES[$i]}"
            local status="${SERVER_STATUSES[$i]}"
            local warnings="${SERVER_WARNINGS[$i]}"
            local criticals="${SERVER_CRITICALS[$i]}"
            
            [ "$first" = true ] && first=false || echo ','
            
            echo '    {'
            echo '      "ip": "'"$ip"'",'
            echo '      "hostname": "'"$hostname"'",'
            echo '      "status": "'"$status"'",'
            echo '      "warnings": "'"$warnings"'",'
            echo '      "criticals": "'"$criticals"'"'
            echo -n '    }'
        done
        
        echo ''
        echo '  ]'
        echo '}'
    } > "$output_file"
    
    log_info "JSON报告已生成: $output_file"
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
        log_info "邮件已发送到: $to"
    elif command -v mutt &>/dev/null; then
        if [ -n "$attachment" ]; then
            echo "$body" | mutt -s "$subject" -a "$attachment" -- "$to"
        else
            echo "$body" | mutt -s "$subject" "$to"
        fi
        log_info "邮件已发送到: $to"
    elif command -v sendmail &>/dev/null; then
        {
            echo "Subject: $subject"
            echo "To: $to"
            echo "Content-Type: text/html; charset=UTF-8"
            echo ""
            cat "$attachment"
        } | sendmail -t
        log_info "邮件已发送到: $to"
    else
        log_warn "未找到邮件发送工具(mailx/mutt/sendmail)"
        log_warn "请手动查看报告: $attachment"
    fi
}

main() {
    local inspect_all=false
    local servers_file="$SERVERS_FILE"
    local output_dir="$REPORT_DIR"
    local report_type="html"
    local timeout=30
    local parallel=5
    local modules=""
    local email=""
    local verbose=false
    local target_ips=()
    local single_host=""
    local single_port=""
    local single_user=""
    local single_password=""
    
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
            --host)
                single_host="$2"
                shift 2
                ;;
            --port)
                single_port="$2"
                shift 2
                ;;
            --user)
                single_user="$2"
                shift 2
                ;;
            --password)
                single_password="$2"
                shift 2
                ;;
            -l|--list)
                list_servers
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
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
    
    if [ -n "$single_host" ]; then
        single_password="${single_password:-$SSH_PASSWORD}"
        SERVER_IPS=("$single_host")
        SERVER_HOSTNAMES=("$single_host")
        SERVER_PORTS=("${single_port:-22}")
        SERVER_USERS=("${single_user:-root}")
        SERVER_PASSWORDS=("$single_password")
        SERVER_SERVICES=("")
    fi
    
    mkdir -p "$output_dir"
    
    local date_str=$(date "+%Y%m%d_%H%M%S")
    LOG_FILE="${LOG_DIR}/inspect_${date_str}.log"
    log_info "巡检开始"
    log_info "日志文件: $LOG_FILE"
    
    load_threshold_config
    
    print_banner
    
    source "${LIB_DIR}/check_deps.sh"
    
    if ! check_deps "interactive"; then
        log_error "依赖检查失败"
        exit 1
    fi
    
    echo ""
    
    SERVER_IPS=()
    SERVER_HOSTNAMES=()
    SERVER_PORTS=()
    SERVER_USERS=()
    SERVER_PASSWORDS=()
    SERVER_SERVICES=()
    SERVER_STATUSES=()
    SERVER_WARNINGS=()
    SERVER_CRITICALS=()
    SERVER_RAW_OUTPUTS=()
    
    if [ ${#SERVER_IPS[@]} -eq 0 ]; then
        if [ "$inspect_all" = true ] || [ ${#target_ips[@]} -eq 0 ]; then
            if [ ! -f "$servers_file" ]; then
                log_error "服务器清单文件不存在: $servers_file"
                exit 1
            fi
            
            while IFS=',' read -r ip hostname port user password business env services tags || [ -n "$ip" ]; do
                [ "$ip" == "ip" ] && continue
                [ -z "$ip" ] && continue
                
                SERVER_IPS+=("$ip")
                SERVER_HOSTNAMES+=("$hostname")
                SERVER_PORTS+=("${port:-22}")
                SERVER_USERS+=("${user:-root}")
                SERVER_PASSWORDS+=("$password")
                SERVER_SERVICES+=("$services")
            done < "$servers_file"
        else
            for ip in "${target_ips[@]}"; do
                local found=false
                if [ -f "$servers_file" ]; then
                    while IFS=',' read -r s_ip s_hostname s_port s_user s_password s_business s_env s_services s_tags || [ -n "$s_ip" ]; do
                        [ "$s_ip" == "ip" ] && continue
                        if [ "$s_ip" == "$ip" ]; then
                            SERVER_IPS+=("$s_ip")
                            SERVER_HOSTNAMES+=("$s_hostname")
                            SERVER_PORTS+=("${s_port:-22}")
                            SERVER_USERS+=("${s_user:-root}")
                            SERVER_PASSWORDS+=("$s_password")
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
                    SERVER_PASSWORDS+=("${SSH_PASSWORD:-}")
                    SERVER_SERVICES+=("")
                fi
            done
        fi
    fi
    
    if [ ${#SERVER_IPS[@]} -eq 0 ]; then
        log_error "没有要巡检的服务器"
        exit 1
    fi
    
    log_info "待巡检服务器数量: ${#SERVER_IPS[@]}"
    log_info "并发数: $parallel"
    log_info "报告类型: $report_type"
    echo ""
    
    OK_COUNT=0
    WARNING_COUNT=0
    CRITICAL_COUNT=0
    
    local temp_dir="${REPORT_DIR}/.temp_${date_str}"
    mkdir -p "$temp_dir"
    
    local running=0
    local pids=()
    local result_files=()
    
    for i in "${!SERVER_IPS[@]}"; do
        local ip="${SERVER_IPS[$i]}"
        local hostname="${SERVER_HOSTNAMES[$i]}"
        local port="${SERVER_PORTS[$i]}"
        local user="${SERVER_USERS[$i]}"
        local password="${SERVER_PASSWORDS[$i]}"
        local services="${SERVER_SERVICES[$i]}"
        local result_file="${temp_dir}/result_${i}.txt"
        
        echo -e "${CYAN}[$((i+1))/${#SERVER_IPS[@]}] 开始巡检: ${hostname} (${ip})${NC}"
        log_info "[$((i+1))/${#SERVER_IPS[@]}] 开始巡检: ${hostname} (${ip})"
        
        (
            inspect_single_server "$ip" "$port" "$user" "$password" "$hostname" "$services" "$modules" "$timeout" "$result_file"
        ) &
        pids+=($!)
        result_files+=("$result_file")
        
        ((running++))
        
        if [ $running -ge $parallel ]; then
            wait -n
            ((running--))
        fi
    done
    
    wait
    
    for i in "${!pids[@]}"; do
        local result_file="${result_files[$i]}"
        local result_line
        
        if [ -f "$result_file" ]; then
            result_line=$(grep "^IP=" "$result_file" 2>/dev/null | head -1 || echo "")
            
            while IFS='=' read -r key value; do
                case "$key" in
                    IP) SERVER_IPS[$i]="$value" ;;
                    HOSTNAME) SERVER_HOSTNAMES[$i]="$value" ;;
                    STATUS) SERVER_STATUSES[$i]="$value" ;;
                    WARNINGS) SERVER_WARNINGS[$i]="$value" ;;
                    CRITICALS) SERVER_CRITICALS[$i]="$value" ;;
                esac
            done < "$result_file"
        else
            SERVER_STATUSES[$i]="CRITICAL"
            SERVER_CRITICALS[$i]="巡检执行失败"
        fi
        
        case "${SERVER_STATUSES[$i]}" in
            OK) 
                echo -e "${GREEN}[OK] ${SERVER_HOSTNAMES[$i]} 巡检完成，状态正常${NC}"
                ((OK_COUNT++))
                ;;
            WARNING) 
                echo -e "${YELLOW}[WARNING] ${SERVER_HOSTNAMES[$i]} 巡检完成，存在警告${NC}"
                ((WARNING_COUNT++))
                ;;
            CRITICAL) 
                echo -e "${RED}[CRITICAL] ${SERVER_HOSTNAMES[$i]} 巡检完成，存在严重问题${NC}"
                ((CRITICAL_COUNT++))
                ;;
        esac
    done
    
    rm -rf "$temp_dir"
    
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
    
    log_info "巡检摘要 - 总数:${#SERVER_IPS[@]} 正常:${OK_COUNT} 警告:${WARNING_COUNT} 严重:${CRITICAL_COUNT}"
    
    local report_file="${output_dir}/inspection_report_${date_str}.${report_type}"
    
    case $report_type in
        text)
            generate_text_report "$report_file"
            ;;
        html)
            generate_html_report "$report_file"
            ;;
        json)
            generate_json_report "$report_file"
            ;;
        *)
            log_warn "未知报告类型: $report_type，使用HTML格式"
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
    echo -e "日志文件: ${LOG_FILE}"
    
    log_info "巡检完成"
    
    if [ "$OVERALL_STATUS" == "CRITICAL" ]; then
        exit 2
    elif [ "$OVERALL_STATUS" == "WARNING" ]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"