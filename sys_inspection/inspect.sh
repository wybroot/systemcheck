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
    if [ ${#PARALLEL_PIDS[@]} -gt 0 ]; then
        for pid in "${PARALLEL_PIDS[@]}"; do
            kill "$pid" 2>/dev/null
        done
    fi
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
    local var_name=$2
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            case "$key" in
                SYS_STATUS|SYS_RESULT|SYS_WARNINGS|SYS_CRITICALS|\
                CPU_STATUS|CPU_CORES|CPU_USAGE|CPU_MODEL|LOAD_1MIN|LOAD_5MIN|LOAD_15MIN|CPU_RESULT|CPU_WARNINGS|CPU_CRITICALS|\
                MEM_STATUS|MEM_USAGE|MEM_USED|MEM_TOTAL|SWAP_TOTAL|SWAP_USED|SWAP_USAGE|MEM_RESULT|MEM_WARNINGS|MEM_CRITICALS|\
                DISK_STATUS|DISK_USAGE|DISK_COUNT|DISK_DETAILS|DISK_RESULT|DISK_WARNINGS|DISK_CRITICALS|\
                NET_STATUS|CONNECTION_ESTABLISHED|CONNECTION_LISTEN|CONNECTION_TIME_WAIT|CONNECTION_COUNT|NET_RESULT|NET_WARNINGS|NET_CRITICALS|\
                PROCESS_STATUS|PROCESS_RUNNING|PROCESS_SLEEPING|PROCESS_ZOMBIE|PROCESS_TOTAL|PROCESS_RESULT|PROCESS_WARNINGS|PROCESS_CRITICALS|\
                SEC_STATUS|LOGIN_FAIL_COUNT|LOGIN_SUCCESS_COUNT|LOGIN_FAIL_USERS|FIREWALL_STATUS|SELINUX_STATUS|SEC_RESULT|SEC_WARNINGS|SEC_CRITICALS)
                    eval "${var_name}[\"${key}\"]=\"${value}\""
                    ;;
            esac
        fi
    done <<< "$output"
}

get_overall_status() {
    local var_name=$1
    local status="OK"
    
    eval "for key in \"\${!${var_name}[@]}\"; do
        if [[ \"\$key\" == *_STATUS ]]; then
            local val=\"\${${var_name}[\$key]}\"
            if [[ \"\$val\" == \"CRITICAL\" ]]; then
                status=\"CRITICAL\"
            elif [[ \"\$val\" == \"WARNING\" && \"\$status\" != \"CRITICAL\" ]]; then
                status=\"WARNING\"
            fi
        fi
    done"
    
    echo "$status"
}

collect_warnings() {
    local var_name=$1
    local warnings=""
    
    eval "for key in \"\${!${var_name}[@]}\"; do
        if [[ \"\$key\" == *_WARNINGS && -n \"\${${var_name}[\$key]}\" ]]; then
            warnings=\"\${warnings}\${${var_name}[\$key]}; \"
        fi
    done"
    
    echo "$warnings"
}

collect_criticals() {
    local var_name=$1
    local criticals=""
    
    eval "for key in \"\${!${var_name}[@]}\"; do
        if [[ \"\$key\" == *_CRITICALS && -n \"\${${var_name}[\$key]}\" ]]; then
            criticals=\"\${criticals}\${${var_name}[\$key]}; \"
        fi
    done"
    
    echo "$criticals"
}

inspect_local() {
    local hostname=$1
    local services=$2
    local modules=$3
    
    local overall_status="OK"
    local all_warnings=""
    local all_criticals=""
    
    log_info "开始巡检本地服务器: $hostname"
    
    echo "===INSPECT_START==="
    
    if [[ "$modules" == *"sys"* ]] || [ -z "$modules" ]; then
        echo "===SYSTEM==="
        if source "${LIB_DIR}/system_check.sh" && check_system; then
            if [[ "$SYS_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$SYS_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$SYS_WARNINGS" ] && all_warnings="${all_warnings}${SYS_WARNINGS}; "
            [ -n "$SYS_CRITICALS" ] && all_criticals="${all_criticals}${SYS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"cpu"* ]] || [ -z "$modules" ]; then
        echo "===CPU==="
        if source "${LIB_DIR}/cpu_check.sh" && check_cpu; then
            if [[ "$CPU_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$CPU_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$CPU_WARNINGS" ] && all_warnings="${all_warnings}${CPU_WARNINGS}; "
            [ -n "$CPU_CRITICALS" ] && all_criticals="${all_criticals}${CPU_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"mem"* ]] || [ -z "$modules" ]; then
        echo "===MEMORY==="
        if source "${LIB_DIR}/memory_check.sh" && check_memory; then
            if [[ "$MEM_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$MEM_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$MEM_WARNINGS" ] && all_warnings="${all_warnings}${MEM_WARNINGS}; "
            [ -n "$MEM_CRITICALS" ] && all_criticals="${all_criticals}${MEM_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"disk"* ]] || [ -z "$modules" ]; then
        echo "===DISK==="
        if source "${LIB_DIR}/disk_check.sh" && check_disk; then
            if [[ "$DISK_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$DISK_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$DISK_WARNINGS" ] && all_warnings="${all_warnings}${DISK_WARNINGS}; "
            [ -n "$DISK_CRITICALS" ] && all_criticals="${all_criticals}${DISK_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"net"* ]] || [ -z "$modules" ]; then
        echo "===NETWORK==="
        if source "${LIB_DIR}/network_check.sh" && check_network; then
            if [[ "$NET_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$NET_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$NET_WARNINGS" ] && all_warnings="${all_warnings}${NET_WARNINGS}; "
            [ -n "$NET_CRITICALS" ] && all_criticals="${all_criticals}${NET_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"proc"* ]] || [ -z "$modules" ]; then
        echo "===PROCESS==="
        export SERVICES="$services"
        if source "${LIB_DIR}/process_check.sh" && check_process; then
            if [[ "$PROCESS_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$PROCESS_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$PROCESS_WARNINGS" ] && all_warnings="${all_warnings}${PROCESS_WARNINGS}; "
            [ -n "$PROCESS_CRITICALS" ] && all_criticals="${all_criticals}${PROCESS_CRITICALS}; "
        fi
    fi
    
    if [[ "$modules" == *"sec"* ]] || [ -z "$modules" ]; then
        echo "===SECURITY==="
        if source "${LIB_DIR}/security_check.sh" && check_security; then
            if [[ "$SEC_STATUS" == "CRITICAL" ]]; then
                overall_status="CRITICAL"
            elif [[ "$SEC_STATUS" == "WARNING" && "$overall_status" != "CRITICAL" ]]; then
                overall_status="WARNING"
            fi
            [ -n "$SEC_WARNINGS" ] && all_warnings="${all_warnings}${SEC_WARNINGS}; "
            [ -n "$SEC_CRITICALS" ] && all_criticals="${all_criticals}${SEC_CRITICALS}; "
        fi
    fi
    
    echo "===INSPECT_END==="
    
    INSPECT_RESULT_STATUS="$overall_status"
    INSPECT_RESULT_WARNINGS="$all_warnings"
    INSPECT_RESULT_CRITICALS="$all_criticals"
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
    
    local use_ip_as_hostname=false
    
    if [[ "$hostname" =~ ^[a-zA-Z0-9]$ ]] && [ ${#hostname} -le 15 ]; then
        use_ip_as_hostname=true
    fi
    
    if [ -n "$password" ]; then
        if ! command -v sshpass &>/dev/null; then
            log_error "需要 sshpass 工具进行密码登录，请安装: yum install -y sshpass 或 apt install -y sshpass"
            return 1
        fi
        
        export SSHPASS="$password"
        if [ "$use_ip_as_hostname" = true ]; then
            ssh_cmd="sshpass -e ssh $ssh_opts -p $port $hostname"
            log_info "使用密码登录: $hostname:$port (密码长度: ${#password})"
        else
            ssh_cmd="sshpass -e ssh $ssh_opts -p $port $user@$ip"
            log_info "使用密码登录: $user@$ip:$port (密码长度: ${#password})"
        fi
    else
        ssh_cmd="ssh $ssh_opts -o BatchMode=yes -p $port $user@$ip"
        log_info "使用免密登录: $user@$ip:$port"
    fi
    
    local test_output
    if ! test_output=$($ssh_cmd "echo 'SSH连接成功'" 2>&1); then
        log_error "SSH连接失败: ${ip}:${port}"
        log_error "错误详情: $test_output"
        
        if [ -n "$password" ]; then
            log_error "提示: 可能的原因包括:"
            log_error "  1. 密码错误"
            log_error "  2. SSH服务未启动或端口错误"
            log_error "  3. 网络不通或防火墙阻止"
            log_error "  4. sshpass工具未安装或版本不兼容"
            log_error ""
            log_error "建议手动测试: sshpass -p '***' ssh -o StrictHostKeyChecking=accept-new -p $port $user@$ip 'echo test'"
        else
            log_error "提示: 可能的原因包括:"
            log_error "  1. 未配置SSH免密登录"
            log_error "  2. SSH服务未启动或端口错误"
            log_error "  3. 网络不通或防火墙阻止"
            log_error "  4. 主机密钥未添加到known_hosts"
            log_error ""
            log_error "建议手动测试: ssh -o StrictHostKeyChecking=accept-new -p $port $user@$ip 'echo test'"
        fi
        
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
    
    CPU_USAGE="0.00"
    if [ -f /proc/stat ]; then
        CPU_LINE1=$(head -1 /proc/stat 2>/dev/null)
        sleep 1
        CPU_LINE2=$(head -1 /proc/stat 2>/dev/null)
        
        if [ -n "$CPU_LINE1" ] && [ -n "$CPU_LINE2" ]; then
            CPU_USAGE=$(awk -v line1="$CPU_LINE1" -v line2="$CPU_LINE2" 'BEGIN {
                split(line1, a1)
                split(line2, a2)
                user1 = a1[2] + 0
                nice1 = a1[3] + 0
                system1 = a1[4] + 0
                idle1 = a1[5] + 0
                iowait1 = a1[6] + 0
                irq1 = a1[7] + 0
                softirq1 = a1[8] + 0
                steal1 = a1[9] + 0
                
                user2 = a2[2] + 0
                nice2 = a2[3] + 0
                system2 = a2[4] + 0
                idle2 = a2[5] + 0
                iowait2 = a2[6] + 0
                irq2 = a2[7] + 0
                softirq2 = a2[8] + 0
                steal2 = a2[9] + 0
                
                total1 = user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1
                total2 = user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2
                total_diff = total2 - total1
                idle_diff = idle2 - idle1
                
                if (total_diff > 0) {
                    printf "%.2f", 100 * (total_diff - idle_diff) / total_diff
                } else {
                    printf "0.00"
                }
            }')
        fi
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
    echo "SWAP_TOTAL=$SWAP_TOTAL"
    echo "SWAP_USED=$SWAP_USED"
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
    DISK_DETAILS=""
    
    DISK_INFO=$(df -hP 2>/dev/null | tail -n +2 | grep -v "tmpfs" | grep -v "devtmpfs" || echo "")
    
    local disk_count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filesystem=$(echo $line | awk '{print $1}')
        size=$(echo $line | awk '{print $2}')
        used=$(echo $line | awk '{print $3}')
        avail=$(echo $line | awk '{print $4}')
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
        
        DISK_DETAILS="${DISK_DETAILS}${filesystem}|${size}|${used}|${avail}|${usage}|${mountpoint}"$'\n'
        ((disk_count++))
    done <<< "$DISK_INFO"
    
    echo "DISK_COUNT=$disk_count"
    echo "DISK_USAGE=$DISK_MAX_USAGE"
    echo "DISK_STATUS=$DISK_STATUS"
    echo "DISK_WARNINGS=$DISK_WARNINGS"
    echo "DISK_CRITICALS=$DISK_CRITICALS"
    echo "DISK_DETAILS=$DISK_DETAILS"
fi

if [[ "$INSPECT_MODULES" == *"net"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===NETWORK==="
    
    CONNECTION_ESTABLISHED=0
    CONNECTION_LISTEN=0
    CONNECTION_TIME_WAIT=0
    CONNECTION_COUNT=0
    
    if command -v ss &>/dev/null; then
        CONNECTION_ESTABLISHED=$(ss -s 2>/dev/null | grep -oP "estab \K\d+" | head -1 || echo 0)
        CONNECTION_LISTEN=$(ss -s 2>/dev/null | grep -oP "listen \K\d+" | head -1 || echo 0)
        CONNECTION_TIME_WAIT=$(ss -s 2>/dev/null | grep -oP "time-wait \K\d+" | head -1 || echo 0)
        CONNECTION_COUNT=$(ss -s 2>/dev/null | grep -oP "estab \K\d+" | head -1 || echo 0)
    elif command -v netstat &>/dev/null; then
        CONNECTION_ESTABLISHED=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
        CONNECTION_LISTEN=$(netstat -an 2>/dev/null | grep -c LISTEN || echo 0)
        CONNECTION_TIME_WAIT=$(netstat -an 2>/dev/null | grep -c TIME_WAIT || echo 0)
        CONNECTION_COUNT=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
    fi
    
    NET_STATUS="OK"
    NET_WARNINGS=""
    NET_CRITICALS=""
    
    if [ "$CONNECTION_COUNT" -gt "$CONNECTION_CRITICAL" ] 2>/dev/null; then
        NET_STATUS="CRITICAL"
        NET_CRITICALS="网络连接总数 ${CONNECTION_COUNT} 超过临界阈值 ${CONNECTION_CRITICAL}"
    elif [ "$CONNECTION_COUNT" -gt "$CONNECTION_WARNING" ] 2>/dev/null; then
        NET_STATUS="WARNING"
        NET_WARNINGS="网络连接总数 ${CONNECTION_COUNT} 超过警告阈值 ${CONNECTION_WARNING}"
    fi
    
    echo "CONNECTION_ESTABLISHED=$CONNECTION_ESTABLISHED"
    echo "CONNECTION_LISTEN=$CONNECTION_LISTEN"
    echo "CONNECTION_TIME_WAIT=$CONNECTION_TIME_WAIT"
    echo "CONNECTION_COUNT=$CONNECTION_COUNT"
    echo "NET_STATUS=$NET_STATUS"
    echo "NET_WARNINGS=$NET_WARNINGS"
    echo "NET_CRITICALS=$NET_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"proc"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===PROCESS==="
    
    PROCESS_RUNNING=0
    PROCESS_SLEEPING=0
    PROCESS_STOPPED=0
    PROCESS_ZOMBIE=0
    PROCESS_TOTAL=0
    
    if command -v ps &>/dev/null; then
        PROCESS_RUNNING=$(ps aux 2>/dev/null | grep -c "R\|Ss" || echo 0)
        PROCESS_SLEEPING=$(ps aux 2>/dev/null | grep -c "S\|Sl" || echo 0)
        PROCESS_ZOMBIE=$(ps aux 2>/dev/null | grep -c "<defunct>" || echo 0)
        PROCESS_TOTAL=$(ps aux 2>/dev/null | wc -l || echo 0)
    fi
    
    PROCESS_STATUS="OK"
    PROCESS_WARNINGS=""
    PROCESS_CRITICALS=""
    
    if [ "$PROCESS_ZOMBIE" -gt "$ZOMBIE_PROCESS_CRITICAL" ] 2>/dev/null; then
        PROCESS_STATUS="CRITICAL"
        PROCESS_CRITICALS="僵尸进程数 ${PROCESS_ZOMBIE} 超过临界阈值 ${ZOMBIE_PROCESS_CRITICAL}"
    elif [ "$PROCESS_ZOMBIE" -gt "$ZOMBIE_PROCESS_WARNING" ] 2>/dev/null; then
        PROCESS_STATUS="WARNING"
        PROCESS_WARNINGS="僵尸进程数 ${PROCESS_ZOMBIE} 超过警告阈值 ${ZOMBIE_PROCESS_WARNING}"
    fi
    
    echo "PROCESS_RUNNING=$PROCESS_RUNNING"
    echo "PROCESS_SLEEPING=$PROCESS_SLEEPING"
    echo "PROCESS_ZOMBIE=$PROCESS_ZOMBIE"
    echo "PROCESS_TOTAL=$PROCESS_TOTAL"
    echo "PROCESS_STATUS=$PROCESS_STATUS"
    echo "PROCESS_WARNINGS=$PROCESS_WARNINGS"
    echo "PROCESS_CRITICALS=$PROCESS_CRITICALS"
fi

if [[ "$INSPECT_MODULES" == *"sec"* ]] || [ -z "$INSPECT_MODULES" ]; then
    echo "===SECURITY==="
    
    LOGIN_FAIL_COUNT=0
    LOGIN_SUCCESS_COUNT=0
    LOGIN_FAIL_USERS=0
    LOGIN_FAIL_IPS=""
    FIREWALL_STATUS="unknown"
    SELINUX_STATUS="unknown"
    
    if [ -f /var/log/secure ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/secure 2>/dev/null || echo 0)
        LOGIN_SUCCESS_COUNT=$(grep -c "Accepted password" /var/log/secure 2>/dev/null || echo 0)
        LOGIN_FAIL_USERS=$(grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $9}' | sort -u | wc -l || echo 0)
        LOGIN_FAIL_IPS=$(grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -rn | head -10 | awk '{print $1 " (" $2 ")"}' || echo "")
    elif [ -f /var/log/auth.log ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
        LOGIN_SUCCESS_COUNT=$(grep -c "Accepted password" /var/log/auth.log 2>/dev/null || echo 0)
        LOGIN_FAIL_USERS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $9}' | sort -u | wc -l || echo 0)
        LOGIN_FAIL_IPS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -rn | head -10 | awk '{print $1 " (" $2 ")"}' || echo "")
    fi
    
    if command -v firewall-cmd &>/dev/null; then
        FIREWALL_STATUS=$(systemctl is-active firewalld 2>/dev/null | grep -q "active" && echo "active" || echo "inactive")
    elif command -v iptables &>/dev/null; then
        FIREWALL_STATUS=$(iptables -L -n 2>/dev/null | grep -c "^[^Chain]" | wc -l | awk '{if($1>0) print "active"; else print "inactive"}')
    fi
    
    if command -v getenforce &>/dev/null; then
        SELINUX_STATUS=$(getenforce 2>/dev/null || echo "unknown")
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
    echo "LOGIN_SUCCESS_COUNT=$LOGIN_SUCCESS_COUNT"
    echo "LOGIN_FAIL_USERS=$LOGIN_FAIL_USERS"
    echo "LOGIN_FAIL_IPS=$LOGIN_FAIL_IPS"
    echo "FIREWALL_STATUS=$FIREWALL_STATUS"
    echo "SELINUX_STATUS=$SELINUX_STATUS"
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
        result_data=$(inspect_local "$hostname" "$services" "$modules")
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
    
    echo "${ip}|${hostname}|${status}|${warnings}|${criticals}|${result_data}"
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
        .fail-users-list { max-height: 150px; overflow-y: auto; font-size: 11px; }
        .fail-user-item { padding: 4px 0; margin-bottom: 4px; border-bottom: 1px solid #eee; }
        .fail-user-item:last-child { border-bottom: none; }
        .fail-user-name { font-weight: 600; color: #495057; display: inline-block; min-width: 80px; }
        .fail-user-ip { color: #dc3545; font-family: monospace; font-size: 11px; }
        .inspection-details { margin-top: 20px; }
        .alert { padding: 10px 15px; border-radius: 5px; margin: 10px 0; }
        .alert.warning { background: #fff3cd; border-left: 4px solid #ffc107; }
        .alert.critical { background: #f8d7da; border-left: 4px solid #dc3545; }
        .inspection-details { margin-top: 20px; }
        .inspection-details h4 { margin-bottom: 15px; color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
        .inspection-details h5 { margin-top: 20px; margin-bottom: 10px; color: #555; font-size: 14px; font-weight: 600; }
        .detail-table { width: 100%; border-collapse: collapse; margin-bottom: 15px; font-size: 13px; }
        .detail-table tr:nth-child(even) { background: #f8f9fa; }
        .detail-table td { padding: 8px 12px; border: 1px solid #dee2e6; }
        .detail-table td:first-child { background: #e9ecef; font-weight: 500; width: 30%; color: #495057; }
        .disk-table { width: 100%; border-collapse: collapse; margin-bottom: 15px; font-size: 12px; }
        .disk-table thead { background: #667eea; color: white; }
        .disk-table th { padding: 10px 8px; text-align: left; font-weight: 600; }
        .disk-table tbody tr:nth-child(even) { background: #f8f9fa; }
        .disk-table tbody tr:hover { background: #e9ecef; }
        .disk-table td { padding: 8px; border: 1px solid #dee2e6; }
        .disk-table tr.critical { background: #fff5f5 !important; }
        .disk-table tr.warning { background: #fffbf0 !important; }
        .usage-badge { padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; display: inline-block; }
        .usage-badge.ok { background: #d4edda; color: #155724; }
        .usage-badge.warning { background: #fff3cd; color: #856404; }
        .usage-badge.critical { background: #f8d7da; color: #721c24; }
        .detail-table tr.warning-row { background: #fffbf0; }
        .detail-table tr.critical-row { background: #fff5f5; }
        .threshold-hint { font-size: 10px; color: #6c757d; margin-left: 8px; font-weight: normal; }
        .threshold-hint .ok { color: #28a745; }
        .threshold-hint .warning { color: #856404; }
        .threshold-hint .critical { color: #dc3545; }
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
            local raw_output="${SERVER_DETAILS[$i]}"
            
            local status_class="ok"
            [ "$status" == "WARNING" ] && status_class="warning"
            [ "$status" == "CRITICAL" ] && status_class="critical"
            
            local status_text="正常"
            [ "$status" == "WARNING" ] && status_text="警告"
            [ "$status" == "CRITICAL" ] && status_text="严重"
            
            echo '<div class="server-card">'
            echo "<div class=\"server-header $status_class\">"
            echo "<h3>${hostname} (${ip})</h3>"
            echo "<span class=\"status-badge $status_class\">$status_text</span>"
            echo '</div><div class="server-body">'
            
            [ -n "$criticals" ] && echo "<div class=\"alert critical\"><strong>严重问题:</strong> ${criticals}</div>"
            [ -n "$warnings" ] && echo "<div class=\"alert warning\"><strong>警告信息:</strong> ${warnings}</div>"
            
            if [ -n "$raw_output" ]; then
                echo '<div class="inspection-details">'
                echo '<h4>巡检详情</h4>'
                
                local cpu_usage_value=""
                local mem_usage_value=""
                local swap_usage_value=""
                local conn_count_value=""
                local zombie_count_value=""
                local login_fail_value=""
                
                local current_section=""
                while IFS= read -r line; do
                    if [[ "$line" =~ ^===([A-Z]+)=== ]]; then
                        local section="${BASH_REMATCH[1]}"
                        case "$section" in
                            SYSTEM)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="system"
                                echo '<h5>系统信息</h5><table class="detail-table">'
                                ;;
                            CPU)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="cpu"
                                echo '<h5>CPU信息</h5><table class="detail-table">'
                                ;;
                            MEMORY)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="memory"
                                echo '<h5>内存信息</h5><table class="detail-table">'
                                ;;
                            DISK)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="disk"
                                echo '<h5>磁盘信息</h5><table class="disk-table">'
                                echo '<thead><tr><th>文件系统</th><th>总大小</th><th>已用</th><th>可用</th><th>使用率</th><th>挂载点</th></tr></thead>'
                                echo '<tbody>'
                                ;;
                            NETWORK)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="network"
                                echo '<h5>网络信息</h5><table class="detail-table">'
                                ;;
                            PROCESS)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="process"
                                echo '<h5>进程信息</h5><table class="detail-table">'
                                ;;
                            SECURITY)
                                [ -n "$current_section" ] && echo '</table>'
                                current_section="security"
                                echo '<h5>安全信息</h5><table class="detail-table">'
                                ;;
                        esac
                    elif [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
                        local key="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        
                        case "$key" in
                            HOSTNAME) echo "<tr><td>主机名</td><td>$value</td></tr>" ;;
                            OS_TYPE) echo "<tr><td>操作系统</td><td>$value</td></tr>" ;;
                            OS_VERSION) echo "<tr><td>系统版本</td><td>$value</td></tr>" ;;
                            KERNEL_VERSION) echo "<tr><td>内核版本</td><td>$value</td></tr>" ;;
                            ARCH) echo "<tr><td>架构</td><td>$value</td></tr>" ;;
                            SYSTEM_TIME) echo "<tr><td>系统时间</td><td>$value</td></tr>" ;;
                            UPTIME_DAYS) echo "<tr><td>运行天数</td><td>$value 天</td></tr>" ;;
                            CPU_CORES) echo "<tr><td>CPU核心数</td><td>$value</td></tr>" ;;
                            CPU_USAGE) 
                                cpu_usage_value="$value"
                                local cpu_usage_int=${value%.*}
                                local cpu_class="ok"
                                local cpu_row_class=""
                                local cpu_threshold="正常 (≤80%)"
                                if [ "$cpu_usage_int" -gt 95 ] 2>/dev/null; then
                                    cpu_class="critical"
                                    cpu_row_class="critical-row"
                                    cpu_threshold="严重 (>95%)"
                                elif [ "$cpu_usage_int" -gt 80 ] 2>/dev/null; then
                                    cpu_class="warning"
                                    cpu_row_class="warning-row"
                                    cpu_threshold="警告 (80-95%)"
                                fi
                                echo "<tr class=\"$cpu_row_class\"><td>CPU使用率</td><td><span class=\"usage-badge $cpu_class\">${value}%</span> <span class=\"threshold-hint $cpu_class\">$cpu_threshold</span></td></tr>" ;;
                            LOAD_1MIN) echo "<tr><td>1分钟负载</td><td>$value</td></tr>" ;;
                            LOAD_5MIN) echo "<tr><td>5分钟负载</td><td>$value</td></tr>" ;;
                            LOAD_15MIN) echo "<tr><td>15分钟负载</td><td>$value</td></tr>" ;;
                            MEM_TOTAL) echo "<tr><td>总内存</td><td>$value MB</td></tr>" ;;
                            MEM_USED) echo "<tr><td>已用内存</td><td>$value MB</td></tr>" ;;
                            MEM_USAGE)
                                mem_usage_value="$value"
                                local mem_usage_int=${value%.*}
                                local mem_class="ok"
                                local mem_row_class=""
                                local mem_threshold="正常 (≤85%)"
                                if [ "$mem_usage_int" -gt 95 ] 2>/dev/null; then
                                    mem_class="critical"
                                    mem_row_class="critical-row"
                                    mem_threshold="严重 (>95%)"
                                elif [ "$mem_usage_int" -gt 85 ] 2>/dev/null; then
                                    mem_class="warning"
                                    mem_row_class="warning-row"
                                    mem_threshold="警告 (85-95%)"
                                fi
                                echo "<tr class=\"$mem_row_class\"><td>内存使用率</td><td><span class=\"usage-badge $mem_class\">${value}%</span> <span class=\"threshold-hint $mem_class\">$mem_threshold</span></td></tr>" ;;
                            SWAP_TOTAL) echo "<tr><td>Swap总大小</td><td>$value MB</td></tr>" ;;
                            SWAP_USED) echo "<tr><td>Swap已用</td><td>$value MB</td></tr>" ;;
                            SWAP_USAGE)
                                swap_usage_value="$value"
                                local swap_usage_int=${value%.*}
                                local swap_class="ok"
                                local swap_row_class=""
                                local swap_threshold="正常 (≤50%)"
                                if [ "$swap_usage_int" -gt 80 ] 2>/dev/null; then
                                    swap_class="critical"
                                    swap_row_class="critical-row"
                                    swap_threshold="严重 (>80%)"
                                elif [ "$swap_usage_int" -gt 50 ] 2>/dev/null; then
                                    swap_class="warning"
                                    swap_row_class="warning-row"
                                    swap_threshold="警告 (50-80%)"
                                fi
                                echo "<tr class=\"$swap_row_class\"><td>Swap使用率</td><td><span class=\"usage-badge $swap_class\">${value}%</span> <span class=\"threshold-hint $swap_class\">$swap_threshold</span></td></tr>" ;;
                            DISK_COUNT)
                                ;;
                            DISK_USAGE)
                                ;;
                            DISK_STATUS)
                                ;;
                            DISK_WARNINGS)
                                ;;
                            DISK_CRITICALS)
                                ;;
                            DISK_DETAILS)
                                if [ -n "$value" ]; then
                                    while IFS='|' read -r fs size used avail usage mount; do
                                        [ -z "$fs" ] && continue
                                        local usage_class="ok"
                                        local usage_int=${usage%.*}
                                        local disk_threshold="正常 (≤85%)"
                                        if [ "$usage_int" -gt 95 ] 2>/dev/null; then
                                            usage_class="critical"
                                            disk_threshold="严重 (>95%)"
                                        elif [ "$usage_int" -gt 85 ] 2>/dev/null; then
                                            usage_class="warning"
                                            disk_threshold="警告 (85-95%)"
                                        fi
                                        echo "<tr class=\"$usage_class\"><td>$fs</td><td>$size</td><td>$used</td><td>$avail</td><td><span class=\"usage-badge $usage_class\">${usage}%</span> <span class=\"threshold-hint $usage_class\">$disk_threshold</span></td><td>$mount</td></tr>"
                                    done <<< "$value"
                                fi
                                ;;
                            CONNECTION_COUNT)
                                conn_count_value="$value"
                                local conn_class="ok"
                                local conn_row_class=""
                                local conn_threshold="正常 (≤5000)"
                                if [ "$value" -gt 10000 ] 2>/dev/null; then
                                    conn_class="critical"
                                    conn_row_class="critical-row"
                                    conn_threshold="严重 (>10000)"
                                elif [ "$value" -gt 5000 ] 2>/dev/null; then
                                    conn_class="warning"
                                    conn_row_class="warning-row"
                                    conn_threshold="警告 (5000-10000)"
                                fi
                                echo "<tr class=\"$conn_row_class\"><td>网络连接总数</td><td><span class=\"usage-badge $conn_class\">$value</span> <span class=\"threshold-hint $conn_class\">$conn_threshold</span></td></tr>" ;;
                            CONNECTION_ESTABLISHED) echo "<tr><td>已建立连接</td><td>$value</td></tr>" ;;
                            CONNECTION_LISTEN) echo "<tr><td>监听端口</td><td>$value</td></tr>" ;;
                            CONNECTION_TIME_WAIT) echo "<tr><td>TIME_WAIT连接</td><td>$value</td></tr>" ;;
                            PROCESS_TOTAL) echo "<tr><td>总进程数</td><td>$value</td></tr>" ;;
                            PROCESS_RUNNING) echo "<tr><td>运行中进程</td><td>$value</td></tr>" ;;
                            PROCESS_SLEEPING) echo "<tr><td>睡眠进程</td><td>$value</td></tr>" ;;
                            PROCESS_ZOMBIE)
                                zombie_count_value="$value"
                                local zombie_class="ok"
                                local zombie_row_class=""
                                local zombie_threshold="正常 (≤10)"
                                if [ "$value" -gt 50 ] 2>/dev/null; then
                                    zombie_class="critical"
                                    zombie_row_class="critical-row"
                                    zombie_threshold="严重 (>50)"
                                elif [ "$value" -gt 10 ] 2>/dev/null; then
                                    zombie_class="warning"
                                    zombie_row_class="warning-row"
                                    zombie_threshold="警告 (10-50)"
                                fi
                                echo "<tr class=\"$zombie_row_class\"><td>僵尸进程数</td><td><span class=\"usage-badge $zombie_class\">$value</span> <span class=\"threshold-hint $zombie_class\">$zombie_threshold</span></td></tr>" ;;
                            LOGIN_FAIL_COUNT)
                                login_fail_value="$value"
                                local login_class="ok"
                                local login_row_class=""
                                local login_threshold="正常 (≤5)"
                                if [ "$value" -gt 10 ] 2>/dev/null; then
                                    login_class="critical"
                                    login_row_class="critical-row"
                                    login_threshold="严重 (>10)"
                                elif [ "$value" -gt 5 ] 2>/dev/null; then
                                    login_class="warning"
                                    login_row_class="warning-row"
                                    login_threshold="警告 (5-10)"
                                fi
                                echo "<tr class=\"$login_row_class\"><td>登录失败次数</td><td><span class=\"usage-badge $login_class\">$value</span> <span class=\"threshold-hint $login_class\">$login_threshold</span></td></tr>" ;;
                            LOGIN_SUCCESS_COUNT) echo "<tr><td>登录成功次数</td><td>$value</td></tr>" ;;
                            LOGIN_FAIL_USERS) echo "<tr><td>失败用户数</td><td>$value</td></tr>" ;;
                            LOGIN_FAIL_IPS) 
                                if [ -n "$value" ]; then
                                    echo "<tr><td>失败用户列表</td><td><div class=\"fail-users-list\">"
                                    echo "$value" | sed 's/| /g' | awk -F'(' '{print "<div class=\"fail-user-item\"><span class=\"fail-user-name\">" $1 "</span><span class=\"fail-user-ip\">" $2 "</span></div>"}'
                                    echo "</div></td></tr>"
                                else
                                    echo "<tr><td>失败用户列表</td><td>无</td></tr>"
                                fi
                                ;;
                            FIREWALL_STATUS)
                                local fw_class="ok"
                                if [ "$value" == "active" ]; then
                                    fw_class="ok"
                                elif [ "$value" == "inactive" ]; then
                                    fw_class="warning"
                                fi
                                echo "<tr><td>防火墙状态</td><td><span class=\"usage-badge $fw_class\">$value</span></td></tr>" ;;
                            SELINUX_STATUS)
                                local selinux_class="ok"
                                if [ "$value" == "enforcing" ]; then
                                    selinux_class="warning"
                                elif [ "$value" == "permissive" ]; then
                                    selinux_class="ok"
                                elif [ "$value" == "disabled" ]; then
                                    selinux_class="ok"
                                elif [ "$value" == "unknown" ]; then
                                    selinux_class="warning"
                                fi
                                echo "<tr><td>SELinux状态</td><td><span class=\"usage-badge $selinux_class\">$value</span></td></tr>" ;;
                        esac
                    fi
                done <<< "$raw_output"
                
                if [ "$current_section" == "disk" ]; then
                    echo '</tbody></table>'
                else
                    [ -n "$current_section" ] && echo '</table>'
                fi
                echo '</div>'
            fi
            
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
    SERVER_DETAILS=()
    
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
        local raw_output=""
        
        if [ -f "$result_file" ]; then
            result_line=$(grep "^IP=" "$result_file" 2>/dev/null | head -1 || echo "")
            
            in_raw_output=false
            while IFS= read -r line; do
                if [[ "$line" == "---RAW_OUTPUT---" ]]; then
                    in_raw_output=true
                    continue
                fi
                if [ "$in_raw_output" = true ]; then
                    raw_output="${raw_output}${line}"$'\n'
                else
                    IFS='=' read -r key value <<< "$line"
                    case "$key" in
                        IP) SERVER_IPS[$i]="$value" ;;
                        HOSTNAME) SERVER_HOSTNAMES[$i]="$value" ;;
                        STATUS) SERVER_STATUSES[$i]="$value" ;;
                        WARNINGS) SERVER_WARNINGS[$i]="$value" ;;
                        CRITICALS) SERVER_CRITICALS[$i]="$value" ;;
                    esac
                fi
            done < "$result_file"
            
            SERVER_DETAILS[$i]="$raw_output"
        else
            SERVER_STATUSES[$i]="CRITICAL"
            SERVER_CRITICALS[$i]="巡检执行失败"
            SERVER_DETAILS[$i]=""
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