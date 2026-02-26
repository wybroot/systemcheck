#!/bin/bash

check_system() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    HOSTNAME=$(hostname 2>/dev/null || echo "未知")
    
    OS_TYPE=""
    OS_VERSION=""
    if [ -f /etc/os-release ]; then
        OS_TYPE=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
        OS_VERSION=$(grep "^VERSION=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="CentOS/RHEL"
        OS_VERSION=$(cat /etc/redhat-release 2>/dev/null)
    elif [ -f /etc/issue ]; then
        OS_TYPE=$(head -1 /etc/issue 2>/dev/null)
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="Debian"
        OS_VERSION=$(cat /etc/debian_version 2>/dev/null)
    else
        OS_TYPE="未知"
        OS_VERSION="未知"
    fi
    
    KERNEL_VERSION=$(uname -r 2>/dev/null || echo "未知")
    ARCH=$(uname -m 2>/dev/null || echo "未知")
    
    SYSTEM_TIME=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")
    
    NTP_STATUS=""
    NTP_SYNC=false
    
    if has_dep "ntpstat" && command -v ntpstat &>/dev/null && ! use_alt "ntpstat"; then
        NTP_OUTPUT=$(ntpstat 2>/dev/null)
        NTP_STATUS=$(echo "$NTP_OUTPUT" | head -2)
        NTP_SYNC=$(echo "$NTP_OUTPUT" | grep -c "synchronised\|synchronized" || echo 0)
    elif has_dep "timedatectl" && command -v timedatectl &>/dev/null && ! use_alt "timedatectl"; then
        NTP_OUTPUT=$(timedatectl status 2>/dev/null)
        NTP_STATUS=$(echo "$NTP_OUTPUT" | grep -E "NTP|System clock|Local time")
        NTP_SYNC=$(echo "$NTP_OUTPUT" | grep -c "NTP synchronized: yes\|NTP service: active" || echo 0)
    else
        if [ -f /proc/uptime ]; then
            NTP_STATUS="无法检测NTP状态(缺少ntpstat/timedatectl)"
        fi
    fi
    
    if [ "$NTP_SYNC" -eq 0 ] && [ -n "$NTP_STATUS" ]; then
        if [ "$status" == "OK" ]; then
            status="WARNING"
        fi
        warnings="$warnings, NTP可能未同步"
    fi
    
    UPTIME_DAYS=0
    if [ -f /proc/uptime ]; then
        UPTIME_SECONDS=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
        UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
    fi
    
    if [ "$UPTIME_DAYS" -lt "$UPTIME_MIN_DAYS" ] 2>/dev/null; then
        if [ "$status" == "OK" ]; then
            status="WARNING"
        fi
        warnings="$warnings, 系统近期已重启(运行${UPTIME_DAYS}天)"
    fi
    
    KERNEL_DMESG=""
    if [ -f /var/log/dmesg ]; then
        KERNEL_DMESG=$(grep -iE "error|fail|warn|critical" /var/log/dmesg 2>/dev/null | tail -5)
    elif command -v dmesg &>/dev/null; then
        KERNEL_DMESG=$(dmesg 2>/dev/null | grep -iE "error|fail|warn|critical" | tail -5)
    fi
    
    result="系统基础信息:\n"
    result="${result}  主机名: ${HOSTNAME}\n"
    result="${result}  操作系统: ${OS_TYPE} ${OS_VERSION}\n"
    result="${result}  内核版本: ${KERNEL_VERSION}\n"
    result="${result}  系统架构: ${ARCH}\n"
    result="${result}  系统时间: ${SYSTEM_TIME}\n"
    result="${result}  运行天数: ${UPTIME_DAYS}天\n"
    if [ -n "$NTP_STATUS" ]; then
        result="${result}  NTP状态:\n${NTP_STATUS}\n"
    fi
    if [ -n "$KERNEL_DMESG" ]; then
        result="${result}  内核错误(最近):\n${KERNEL_DMESG}"
    fi
    
    echo "SYS_STATUS=$status"
    echo "HOSTNAME=$HOSTNAME"
    echo "OS_TYPE=$OS_TYPE"
    echo "OS_VERSION=$OS_VERSION"
    echo "KERNEL_VERSION=$KERNEL_VERSION"
    echo "ARCH=$ARCH"
    echo "SYSTEM_TIME=$SYSTEM_TIME"
    echo "UPTIME_DAYS=$UPTIME_DAYS"
    echo "SYS_RESULT=$result"
    echo "SYS_WARNINGS=$warnings"
    echo "SYS_CRITICALS=$criticals"
}