#!/bin/bash

check_memory() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    MEM_TOTAL=0
    MEM_USED=0
    MEM_USAGE=0
    SWAP_TOTAL=0
    SWAP_USED=0
    SWAP_USAGE=0
    MEM_ACTUAL_USED=0
    
    if has_dep "free" && ! use_alt "free"; then
        MEM_INFO=$(free -m 2>/dev/null | grep "Mem:")
        MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
        MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
        MEM_BUFFERS=$(echo $MEM_INFO | awk '{print $6}')
        MEM_CACHED=$(free -m 2>/dev/null | grep "Mem:" | awk '{print $7}')
        
        if [ -n "$MEM_BUFFERS" ] && [ -n "$MEM_CACHED" ]; then
            MEM_ACTUAL_USED=$((MEM_USED - MEM_BUFFERS - MEM_CACHED))
            [ $MEM_ACTUAL_USED -lt 0 ] && MEM_ACTUAL_USED=0
        else
            MEM_ACTUAL_USED=$MEM_USED
        fi
        
        if [ "$MEM_TOTAL" -gt 0 ]; then
            if has_dep "bc" && ! use_alt "bc"; then
                MEM_USAGE=$(echo "scale=2; $MEM_ACTUAL_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null)
            else
                MEM_USAGE=$(awk "BEGIN {printf \"%.2f\", $MEM_ACTUAL_USED * 100 / $MEM_TOTAL}")
            fi
        fi
        
        SWAP_INFO=$(free -m 2>/dev/null | grep "Swap:")
        SWAP_TOTAL=$(echo $SWAP_INFO | awk '{print $2}')
        SWAP_USED=$(echo $SWAP_INFO | awk '{print $3}')
        
        if [ "$SWAP_TOTAL" -gt 0 ]; then
            if has_dep "bc" && ! use_alt "bc"; then
                SWAP_USAGE=$(echo "scale=2; $SWAP_USED * 100 / $SWAP_TOTAL" | bc 2>/dev/null)
            else
                SWAP_USAGE=$(awk "BEGIN {printf \"%.2f\", $SWAP_USED * 100 / $SWAP_TOTAL}")
            fi
        fi
    else
        if [ -f /proc/meminfo ]; then
            MEM_TOTAL=$(grep "MemTotal:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            MEM_FREE=$(grep "MemFree:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            MEM_BUFFERS=$(grep "Buffers:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            MEM_CACHED=$(grep "Cached:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            
            MEM_USED=$((MEM_TOTAL - MEM_FREE - MEM_BUFFERS - MEM_CACHED))
            [ $MEM_USED -lt 0 ] && MEM_USED=0
            MEM_ACTUAL_USED=$MEM_USED
            
            if [ "$MEM_TOTAL" -gt 0 ]; then
                MEM_USAGE=$(awk "BEGIN {printf \"%.2f\", $MEM_USED * 100 / $MEM_TOTAL}")
            fi
            
            SWAP_TOTAL=$(grep "SwapTotal:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            SWAP_FREE=$(grep "SwapFree:" /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}')
            SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
            [ $SWAP_USED -lt 0 ] && SWAP_USED=0
            
            if [ "$SWAP_TOTAL" -gt 0 ]; then
                SWAP_USAGE=$(awk "BEGIN {printf \"%.2f\", $SWAP_USED * 100 / $SWAP_TOTAL}")
            fi
        fi
    fi
    
    MEM_TOTAL=${MEM_TOTAL:-0}
    MEM_USAGE=${MEM_USAGE:-0}
    SWAP_USAGE=${SWAP_USAGE:-0}
    
    if has_dep "bc" && ! use_alt "bc"; then
        if (( $(echo "$MEM_USAGE > $MEM_USAGE_CRITICAL" | bc -l 2>/dev/null) )); then
            status="CRITICAL"
            criticals="内存使用率 ${MEM_USAGE}% 超过临界阈值 ${MEM_USAGE_CRITICAL}%"
        elif (( $(echo "$MEM_USAGE > $MEM_USAGE_WARNING" | bc -l 2>/dev/null) )); then
            status="WARNING"
            warnings="内存使用率 ${MEM_USAGE}% 超过警告阈值 ${MEM_USAGE_WARNING}%"
        fi
        
        if (( $(echo "$SWAP_USAGE > $SWAP_USAGE_CRITICAL" | bc -l 2>/dev/null) )); then
            [ "$status" != "CRITICAL" ] && status="CRITICAL"
            criticals="$criticals, Swap使用率 ${SWAP_USAGE}% 超过临界阈值 ${SWAP_USAGE_CRITICAL}%"
        elif (( $(echo "$SWAP_USAGE > $SWAP_USAGE_WARNING" | bc -l 2>/dev/null) )); then
            [ "$status" == "OK" ] && status="WARNING"
            warnings="$warnings, Swap使用率 ${SWAP_USAGE}% 超过警告阈值 ${SWAP_USAGE_WARNING}%"
        fi
    else
        local mem_usage_int=${MEM_USAGE%.*}
        local swap_usage_int=${SWAP_USAGE%.*}
        
        if [ "$mem_usage_int" -gt "$MEM_USAGE_CRITICAL" ] 2>/dev/null; then
            status="CRITICAL"
            criticals="内存使用率 ${MEM_USAGE}% 超过临界阈值 ${MEM_USAGE_CRITICAL}%"
        elif [ "$mem_usage_int" -gt "$MEM_USAGE_WARNING" ] 2>/dev/null; then
            status="WARNING"
            warnings="内存使用率 ${MEM_USAGE}% 超过警告阈值 ${MEM_USAGE_WARNING}%"
        fi
        
        if [ "$swap_usage_int" -gt "$SWAP_USAGE_CRITICAL" ] 2>/dev/null; then
            [ "$status" != "CRITICAL" ] && status="CRITICAL"
            criticals="$criticals, Swap使用率 ${SWAP_USAGE}% 超过临界阈值 ${SWAP_USAGE_CRITICAL}%"
        elif [ "$swap_usage_int" -gt "$SWAP_USAGE_WARNING" ] 2>/dev/null; then
            [ "$status" == "OK" ] && status="WARNING"
            warnings="$warnings, Swap使用率 ${SWAP_USAGE}% 超过警告阈值 ${SWAP_USAGE_WARNING}%"
        fi
    fi
    
    if has_dep "ps" && ! use_alt "ps"; then
        TOP_MEM_PROCESSES=$(ps -eo pid,user,%mem,comm --sort=-%mem 2>/dev/null | head -n 6 | tail -n 5)
    else
        TOP_MEM_PROCESSES="无法获取(缺少ps命令)"
    fi
    
    result="内存检查结果:\n"
    result="${result}  内存总量: ${MEM_TOTAL}MB\n"
    result="${result}  内存使用: ${MEM_USED}MB (实际使用约${MEM_ACTUAL_USED}MB)\n"
    result="${result}  内存使用率: ${MEM_USAGE}%\n"
    result="${result}  Swap总量: ${SWAP_TOTAL}MB\n"
    result="${result}  Swap使用: ${SWAP_USED}MB\n"
    result="${result}  Swap使用率: ${SWAP_USAGE}%\n"
    result="${result}  TOP5 内存进程:\n${TOP_MEM_PROCESSES}"
    
    echo "MEM_STATUS=$status"
    echo "MEM_TOTAL=$MEM_TOTAL"
    echo "MEM_USED=$MEM_USED"
    echo "MEM_USAGE=$MEM_USAGE"
    echo "SWAP_TOTAL=$SWAP_TOTAL"
    echo "SWAP_USED=$SWAP_USED"
    echo "SWAP_USAGE=$SWAP_USAGE"
    echo "MEM_RESULT=$result"
    echo "MEM_WARNINGS=$warnings"
    echo "MEM_CRITICALS=$criticals"
}