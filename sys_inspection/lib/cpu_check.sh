#!/bin/bash

check_cpu() {
    local result=""
    CPU_STATUS="OK"
    CPU_WARNINGS=""
    CPU_CRITICALS=""
    
    if has_dep "lscpu" && ! use_alt "lscpu"; then
        CPU_CORES=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
        CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | sed 's/Model name:\s*//')
    else
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
        CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
        [ -z "$CPU_MODEL" ] && CPU_MODEL="未知(替代方案)"
    fi
    
    CPU_CORES=${CPU_CORES:-1}
    
    if has_dep "mpstat" && ! use_alt "mpstat"; then
        CPU_IDLE=$(mpstat 1 1 2>/dev/null | awk '/Average/ {print $NF}')
        if has_dep "bc" && ! use_alt "bc"; then
            CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null)
        else
            CPU_USAGE=$(awk "BEGIN {printf \"%.2f\", 100 - $CPU_IDLE}")
        fi
    else
        if [ -f /proc/stat ]; then
            read cpu user nice system idle iowait irq softirq steal guest guest_nice < <(head -1 /proc/stat)
            sleep 1
            read cpu2 user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2 < <(head -1 /proc/stat)
            
            local total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
            local total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
            local idle_diff=$((idle2 - idle))
            local total_diff=$((total2 - total1))
            
            if [ $total_diff -gt 0 ]; then
                if has_dep "bc" && ! use_alt "bc"; then
                    CPU_USAGE=$(echo "scale=2; 100 * ($total_diff - $idle_diff) / $total_diff" | bc 2>/dev/null)
                else
                    CPU_USAGE=$(awk "BEGIN {printf \"%.2f\", 100 * ($total_diff - $idle_diff) / $total_diff}")
                fi
            else
                CPU_USAGE=0
            fi
        else
            if has_dep "top" && ! use_alt "top"; then
                CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
            else
                CPU_USAGE=0
            fi
        fi
    fi
    
    CPU_USAGE=${CPU_USAGE:-0}
    
    LOAD_AVG=$(cat /proc/loadavg 2>/dev/null | awk '{print $1,$2,$3}')
    LOAD_1MIN=$(echo $LOAD_AVG | awk '{print $1}')
    LOAD_5MIN=$(echo $LOAD_AVG | awk '{print $2}')
    LOAD_15MIN=$(echo $LOAD_AVG | awk '{print $3}')
    
    if has_dep "bc" && ! use_alt "bc"; then
        LOAD_WARNING=$(echo "$CPU_CORES * $CPU_LOAD_WARNING_RATIO" | bc 2>/dev/null)
        LOAD_CRITICAL=$(echo "$CPU_CORES * $CPU_LOAD_CRITICAL_RATIO" | bc 2>/dev/null)
    else
        LOAD_WARNING=$(awk "BEGIN {printf \"%.2f\", $CPU_CORES * $CPU_LOAD_WARNING_RATIO}")
        LOAD_CRITICAL=$(awk "BEGIN {printf \"%.2f\", $CPU_CORES * $CPU_LOAD_CRITICAL_RATIO}")
    fi
    
    LOAD_WARNING=${LOAD_WARNING:-$CPU_CORES}
    LOAD_CRITICAL=${LOAD_CRITICAL:-$CPU_CORES}
    
    if has_dep "bc" && ! use_alt "bc"; then
        if (( $(echo "$CPU_USAGE > $CPU_USAGE_CRITICAL" | bc -l 2>/dev/null) )); then
            CPU_STATUS="CRITICAL"
            CPU_CRITICALS="CPU使用率 ${CPU_USAGE}% 超过临界阈值 ${CPU_USAGE_CRITICAL}%"
        elif (( $(echo "$CPU_USAGE > $CPU_USAGE_WARNING" | bc -l 2>/dev/null) )); then
            CPU_STATUS="WARNING"
            CPU_WARNINGS="CPU使用率 ${CPU_USAGE}% 超过警告阈值 ${CPU_USAGE_WARNING}%"
        fi
        
        if (( $(echo "$LOAD_1MIN > $LOAD_CRITICAL" | bc -l 2>/dev/null) )); then
            [ "$CPU_STATUS" != "CRITICAL" ] && CPU_STATUS="CRITICAL"
            CPU_CRITICALS="$CPU_CRITICALS, 系统负载 ${LOAD_1MIN} 超过临界阈值"
        elif (( $(echo "$LOAD_1MIN > $LOAD_WARNING" | bc -l 2>/dev/null) )); then
            [ "$CPU_STATUS" == "OK" ] && CPU_STATUS="WARNING"
            CPU_WARNINGS="$CPU_WARNINGS, 系统负载 ${LOAD_1MIN} 超过警告阈值"
        fi
    else
        local cpu_usage_int=${CPU_USAGE%.*}
        local load_1min_int=${LOAD_1MIN%.*}
        local load_warning_int=${LOAD_WARNING%.*}
        local load_critical_int=${LOAD_CRITICAL%.*}
        
        if [ "$cpu_usage_int" -gt "$CPU_USAGE_CRITICAL" ] 2>/dev/null; then
            CPU_STATUS="CRITICAL"
            CPU_CRITICALS="CPU使用率 ${CPU_USAGE}% 超过临界阈值 ${CPU_USAGE_CRITICAL}%"
        elif [ "$cpu_usage_int" -gt "$CPU_USAGE_WARNING" ] 2>/dev/null; then
            CPU_STATUS="WARNING"
            CPU_WARNINGS="CPU使用率 ${CPU_USAGE}% 超过警告阈值 ${CPU_USAGE_WARNING}%"
        fi
        
        if [ "$load_1min_int" -gt "$load_critical_int" ] 2>/dev/null; then
            [ "$CPU_STATUS" != "CRITICAL" ] && CPU_STATUS="CRITICAL"
            CPU_CRITICALS="$CPU_CRITICALS, 系统负载 ${LOAD_1MIN} 超过临界阈值"
        elif [ "$load_1min_int" -gt "$load_warning_int" ] 2>/dev/null; then
            [ "$CPU_STATUS" == "OK" ] && CPU_STATUS="WARNING"
            CPU_WARNINGS="$CPU_WARNINGS, 系统负载 ${LOAD_1MIN} 超过警告阈值"
        fi
    fi
    
    if has_dep "ps" && ! use_alt "ps"; then
        TOP_CPU_PROCESSES=$(ps -eo pid,user,%cpu,comm --sort=-%cpu 2>/dev/null | head -n 6 | tail -n 5)
    else
        TOP_CPU_PROCESSES="无法获取(缺少ps命令)"
    fi
    
    result="CPU检查结果:\n"
    result="${result}  CPU型号: ${CPU_MODEL:-未知}\n"
    result="${result}  CPU核心数: ${CPU_CORES}\n"
    result="${result}  CPU使用率: ${CPU_USAGE}%\n"
    result="${result}  系统负载: 1分钟=${LOAD_1MIN} 5分钟=${LOAD_5MIN} 15分钟=${LOAD_15MIN}\n"
    result="${result}  负载阈值: 警告=${LOAD_WARNING} 临界=${LOAD_CRITICAL}\n"
    result="${result}  TOP5 CPU进程:\n${TOP_CPU_PROCESSES}"
    
    echo "CPU_STATUS=$CPU_STATUS"
    echo "CPU_CORES=$CPU_CORES"
    echo "CPU_USAGE=$CPU_USAGE"
    echo "CPU_MODEL=$CPU_MODEL"
    echo "LOAD_1MIN=$LOAD_1MIN"
    echo "LOAD_5MIN=$LOAD_5MIN"
    echo "LOAD_15MIN=$LOAD_15MIN"
    echo "CPU_RESULT=$result"
    echo "CPU_WARNINGS=$CPU_WARNINGS"
    echo "CPU_CRITICALS=$CPU_CRITICALS"
}
