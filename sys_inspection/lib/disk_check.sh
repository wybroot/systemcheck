#!/bin/bash

check_disk() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    DISK_RESULT=""
    if has_dep "df" && ! use_alt "df"; then
        DISK_INFO=$(df -hP 2>/dev/null | grep -v "Filesystem" | grep -v "tmpfs" | grep -v "devtmpfs")
        
        while IFS= read -r line; do
            local filesystem=$(echo $line | awk '{print $1}')
            local size=$(echo $line | awk '{print $2}')
            local used=$(echo $line | awk '{print $3}')
            local avail=$(echo $line | awk '{print $4}')
            local usage=$(echo $line | awk '{print $5}' | tr -d '%')
            local mountpoint=$(echo $line | awk '{print $6}')
            
            DISK_RESULT="${DISK_RESULT}  ${mountpoint}: 总量=${size} 已用=${used} 可用=${avail} 使用率=${usage}%\n"
            
            if [ "$usage" -gt "$DISK_USAGE_CRITICAL" ] 2>/dev/null; then
                status="CRITICAL"
                criticals="$criticals, 挂载点${mountpoint}使用率${usage}%超过临界阈值${DISK_USAGE_CRITICAL}%"
            elif [ "$usage" -gt "$DISK_USAGE_WARNING" ] 2>/dev/null; then
                [ "$status" == "OK" ] && status="WARNING"
                warnings="$warnings, 挂载点${mountpoint}使用率${usage}%超过警告阈值${DISK_USAGE_WARNING}%"
            fi
        done <<< "$DISK_INFO"
        
        INODE_RESULT=""
        INODE_INFO=$(df -iP 2>/dev/null | grep -v "Filesystem" | grep -v "tmpfs" | grep -v "devtmpfs")
        
        while IFS= read -r line; do
            local iusage=$(echo $line | awk '{print $5}' | tr -d '%')
            local mountpoint=$(echo $line | awk '{print $6}')
            
            if [ -n "$iusage" ] && [ "$iusage" -gt 0 ]; then
                INODE_RESULT="${INODE_RESULT}  ${mountpoint}: Inode使用率=${iusage}%\n"
                
                if [ "$iusage" -gt "$INODE_USAGE_CRITICAL" ] 2>/dev/null; then
                    [ "$status" != "CRITICAL" ] && status="CRITICAL"
                    criticals="$criticals, 挂载点${mountpoint} Inode使用率${iusage}%超过临界阈值"
                elif [ "$iusage" -gt "$INODE_USAGE_WARNING" ] 2>/dev/null; then
                    [ "$status" == "OK" ] && status="WARNING"
                    warnings="$warnings, 挂载点${mountpoint} Inode使用率${iusage}%超过警告阈值"
                fi
            fi
        done <<< "$INODE_INFO"
    else
        if [ -f /proc/mounts ]; then
            while IFS= read -r line; do
                local device=$(echo $line | awk '{print $1}')
                local mountpoint=$(echo $line | awk '{print $2}')
                
                if [[ "$device" == /dev/* ]]; then
                    if [ -d "$mountpoint" ]; then
                        local size_kb=$(df -k "$mountpoint" 2>/dev/null | tail -1 | awk '{print $2}')
                        local used_kb=$(df -k "$mountpoint" 2>/dev/null | tail -1 | awk '{print $3}')
                        local avail_kb=$(df -k "$mountpoint" 2>/dev/null | tail -1 | awk '{print $4}')
                        
                        if [ -n "$size_kb" ] && [ "$size_kb" -gt 0 ]; then
                            local usage=$((used_kb * 100 / size_kb))
                            local size_gb=$((size_kb / 1024 / 1024))
                            local used_gb=$((used_kb / 1024 / 1024))
                            
                            DISK_RESULT="${DISK_RESULT}  ${mountpoint}: 总量=${size_gb}G 已用=${used_gb}G 使用率=${usage}%\n"
                            
                            if [ "$usage" -gt "$DISK_USAGE_CRITICAL" ]; then
                                status="CRITICAL"
                                criticals="$criticals, 挂载点${mountpoint}使用率${usage}%超过临界阈值"
                            elif [ "$usage" -gt "$DISK_USAGE_WARNING" ]; then
                                [ "$status" == "OK" ] && status="WARNING"
                                warnings="$warnings, 挂载点${mountpoint}使用率${usage}%超过警告阈值"
                            fi
                        fi
                    fi
                fi
            done < /proc/mounts
        fi
    fi
    
    IO_WAIT=""
    if has_dep "iostat" && ! use_alt "iostat"; then
        IO_WAIT=$(iostat -x 1 2 2>/dev/null | tail -n +4 | awk '{sum+=$NF} END {printf "%.2f", sum/NR}')
        
        if [ -n "$IO_WAIT" ]; then
            if has_dep "bc" && ! use_alt "bc"; then
                if (( $(echo "$IO_WAIT > $IO_WAIT_CRITICAL" | bc -l 2>/dev/null) )); then
                    [ "$status" != "CRITICAL" ] && status="CRITICAL"
                    criticals="$criticals, IO等待时间${IO_WAIT}%超过临界阈值${IO_WAIT_CRITICAL}%"
                elif (( $(echo "$IO_WAIT > $IO_WAIT_WARNING" | bc -l 2>/dev/null) )); then
                    [ "$status" == "OK" ] && status="WARNING"
                    warnings="$warnings, IO等待时间${IO_WAIT}%超过警告阈值${IO_WAIT_WARNING}%"
                fi
            else
                local io_wait_int=${IO_WAIT%.*}
                if [ "$io_wait_int" -gt "$IO_WAIT_CRITICAL" ]; then
                    [ "$status" != "CRITICAL" ] && status="CRITICAL"
                    criticals="$criticals, IO等待时间${IO_WAIT}%超过临界阈值"
                elif [ "$io_wait_int" -gt "$IO_WAIT_WARNING" ]; then
                    [ "$status" == "OK" ] && status="WARNING"
                    warnings="$warnings, IO等待时间${IO_WAIT}%超过警告阈值"
                fi
            fi
        fi
    else
        if [ -f /proc/diskstats ]; then
            IO_WAIT="无法精确计算(缺少iostat)"
        fi
    fi
    
    LARGE_FILES=""
    if has_dep "find" && ! use_alt "find"; then
        LARGE_FILES=$(find /var /home /tmp /opt /data -type f -size +1G 2>/dev/null | head -n 10)
    else
        LARGE_FILES="跳过大文件扫描(缺少find命令)"
    fi
    
    result="磁盘检查结果:\n"
    result="${result}  磁盘使用情况:\n${DISK_RESULT}"
    if [ -n "$INODE_RESULT" ]; then
        result="${result}  Inode使用情况:\n${INODE_RESULT}"
    fi
    if [ -n "$IO_WAIT" ]; then
        result="${result}  IO等待: ${IO_WAIT}%\n"
    fi
    if [ -n "$LARGE_FILES" ] && [ "$LARGE_FILES" != "跳过大文件扫描(缺少find命令)" ]; then
        result="${result}  大文件(>1G):\n${LARGE_FILES}"
    fi
    
    echo "DISK_STATUS=$status"
    echo "DISK_RESULT=$result"
    echo "DISK_WARNINGS=$warnings"
    echo "DISK_CRITICALS=$criticals"
    echo "DISK_IO_WAIT=$IO_WAIT"
}