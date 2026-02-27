#!/bin/bash

check_memory() {
    local result=""
    MEM_STATUS="OK"
    MEM_WARNINGS=""
    MEM_CRITICALS=""
    
    MEM_TOTAL=0
    MEM_USED=0
    MEM_FREE=0
    MEM_USAGE=0
    SWAP_TOTAL=0
    SWAP_USED=0
    SWAP_FREE=0
    SWAP_USAGE=0
    
    if [ -f /proc/meminfo ]; then
        MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        MEM_FREE=$(grep MemFree /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        BUFFERS=$(grep Buffers /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        CACHED=$(grep Cached /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        
        if [ -n "$MEM_AVAILABLE" ]; then
            MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
        else
            MEM_USED=$((MEM_TOTAL - MEM_FREE - BUFFERS - CACHED))
        fi
        
        if [ "$MEM_TOTAL" -gt 0 ]; then
            MEM_USAGE=$((MEM_USED * 100 / MEM_TOTAL))
        fi
        
        SWAP_TOTAL=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        SWAP_FREE=$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
        SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
        
        if [ "$SWAP_TOTAL" -gt 0 ]; then
            SWAP_USAGE=$((SWAP_USED * 100 / SWAP_TOTAL))
        fi
    else
        if has_dep "free" && ! use_alt "free"; then
            FREE_OUTPUT=$(free -m 2>/dev/null | grep -E "Mem|Swap")
            MEM_TOTAL=$(echo "$FREE_OUTPUT" | grep Mem | awk '{print $2}')
            MEM_USED=$(echo "$FREE_OUTPUT" | grep Mem | awk '{print $3}')
            MEM_USAGE=$((MEM_USED * 100 / MEM_TOTAL))
            SWAP_TOTAL=$(echo "$FREE_OUTPUT" | grep Swap | awk '{print $2}')
            SWAP_USED=$(echo "$FREE_OUTPUT" | grep Swap | awk '{print $3}')
            [ "$SWAP_TOTAL" -gt 0 ] && SWAP_USAGE=$((SWAP_USED * 100 / SWAP_TOTAL))
        fi
    fi
    
    if [ "$MEM_USAGE" -gt "$MEM_USAGE_CRITICAL" ] 2>/dev/null; then
        MEM_STATUS="CRITICAL"
        MEM_CRITICALS="内存使用率 ${MEM_USAGE}% 超过临界阈值 ${MEM_USAGE_CRITICAL}%"
    elif [ "$MEM_USAGE" -gt "$MEM_USAGE_WARNING" ] 2>/dev/null; then
        MEM_STATUS="WARNING"
        MEM_WARNINGS="内存使用率 ${MEM_USAGE}% 超过警告阈值 ${MEM_USAGE_WARNING}%"
    fi
    
    if [ "$SWAP_USAGE" -gt "$SWAP_USAGE_CRITICAL" ] 2>/dev/null; then
        [ "$MEM_STATUS" != "CRITICAL" ] && MEM_STATUS="CRITICAL"
        MEM_CRITICALS="$MEM_CRITICALS, Swap使用率 ${SWAP_USAGE}% 超过临界阈值 ${SWAP_USAGE_CRITICAL}%"
    elif [ "$SWAP_USAGE" -gt "$SWAP_USAGE_WARNING" ] 2>/dev/null; then
        [ "$MEM_STATUS" == "OK" ] && MEM_STATUS="WARNING"
        MEM_WARNINGS="$MEM_WARNINGS, Swap使用率 ${SWAP_USAGE}% 超过警告阈值 ${SWAP_USAGE_WARNING}%"
    fi
    
    OOM_CHECK=""
    if [ -f /var/log/messages ]; then
        OOM_COUNT=$(grep -c "Out of memory" /var/log/messages 2>/dev/null || true)
        if [ "$OOM_COUNT" -gt 0 ]; then
            OOM_CHECK="发现 ${OOM_COUNT} 次OOM事件"
            if [ "$MEM_STATUS" == "OK" ]; then
                MEM_STATUS="WARNING"
            fi
            MEM_WARNINGS="$MEM_WARNINGS, 发现OOM事件"
        fi
    elif [ -f /var/log/syslog ]; then
        OOM_COUNT=$(grep -c "Out of memory" /var/log/syslog 2>/dev/null || true)
        if [ "$OOM_COUNT" -gt 0 ]; then
            OOM_CHECK="发现 ${OOM_COUNT} 次OOM事件"
            if [ "$MEM_STATUS" == "OK" ]; then
                MEM_STATUS="WARNING"
            fi
            MEM_WARNINGS="$MEM_WARNINGS, 发现OOM事件"
        fi
    fi
    
    TOP_MEM_PROCESSES=""
    if has_dep "ps" && ! use_alt "ps"; then
        TOP_MEM_PROCESSES=$(ps -eo pid,user,%mem,comm --sort=-%mem 2>/dev/null | head -n 6 | tail -n 5)
    else
        TOP_MEM_PROCESSES="无法获取(缺少ps命令)"
    fi
    
    result="内存检查结果:\n"
    result="${result}  内存总量: ${MEM_TOTAL}MB\n"
    result="${result}  内存已用: ${MEM_USED}MB\n"
    result="${result}  内存使用率: ${MEM_USAGE}%\n"
    result="${result}  Swap总量: ${SWAP_TOTAL}MB\n"
    result="${result}  Swap已用: ${SWAP_USED}MB\n"
    result="${result}  Swap使用率: ${SWAP_USAGE}%\n"
    if [ -n "$OOM_CHECK" ]; then
        result="${result}  OOM检查: ${OOM_CHECK}\n"
    fi
    result="${result}  TOP5 内存进程:\n${TOP_MEM_PROCESSES}"
    
    echo "MEM_STATUS=$MEM_STATUS"
    echo "MEM_TOTAL=$MEM_TOTAL"
    echo "MEM_USED=$MEM_USED"
    echo "MEM_USAGE=$MEM_USAGE"
    echo "SWAP_TOTAL=$SWAP_TOTAL"
    echo "SWAP_USED=$SWAP_USED"
    echo "SWAP_USAGE=$SWAP_USAGE"
    echo "MEM_RESULT=$result"
    echo "MEM_WARNINGS=$MEM_WARNINGS"
    echo "MEM_CRITICALS=$MEM_CRITICALS"
}
