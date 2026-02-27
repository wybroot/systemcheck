#!/bin/bash

check_process() {
    local result=""
    PROCESS_STATUS="OK"
    PROCESS_WARNINGS=""
    PROCESS_CRITICALS=""
    
    PROCESS_TOTAL=0
    PROCESS_RUNNING=0
    PROCESS_SLEEPING=0
    ZOMBIE_COUNT=0
    
    if has_dep "ps" && ! use_alt "ps"; then
        PROCESS_TOTAL=$(ps aux 2>/dev/null | wc -l)
        PROCESS_RUNNING=$(ps aux 2>/dev/null | grep -c "R\|Ss" || true)
        PROCESS_SLEEPING=$(ps aux 2>/dev/null | grep -c "S\|Sl" || true)
        ZOMBIE_COUNT=$(ps aux 2>/dev/null | grep -c "<defunct>" || true)
    else
        if [ -f /proc/stat ]; then
            PROCESS_TOTAL=$(grep "procs_running\|procs_blocked" /proc/stat 2>/dev/null | awk '{sum+=$2} END {print sum}')
        fi
        ZOMBIE_COUNT=0
    fi
    
    PROCESS_TOTAL=${PROCESS_TOTAL:-0}
    PROCESS_RUNNING=${PROCESS_RUNNING:-0}
    PROCESS_SLEEPING=${PROCESS_SLEEPING:-0}
    ZOMBIE_COUNT=${ZOMBIE_COUNT:-0}
    
    if [ "$ZOMBIE_COUNT" -gt "$ZOMBIE_PROCESS_CRITICAL" ] 2>/dev/null; then
        PROCESS_STATUS="CRITICAL"
        PROCESS_CRITICALS="僵尸进程数${ZOMBIE_COUNT}超过临界阈值${ZOMBIE_PROCESS_CRITICAL}"
    elif [ "$ZOMBIE_COUNT" -gt "$ZOMBIE_PROCESS_WARNING" ] 2>/dev/null; then
        PROCESS_STATUS="WARNING"
        PROCESS_WARNINGS="僵尸进程数${ZOMBIE_COUNT}超过警告阈值${ZOMBIE_PROCESS_WARNING}"
    fi
    
    ZOMBIE_LIST=""
    if [ "$ZOMBIE_COUNT" -gt 0 ]; then
        if has_dep "ps" && ! use_alt "ps"; then
            ZOMBIE_LIST=$(ps aux 2>/dev/null | grep "<defunct>" | head -5)
        fi
    fi
    
    SERVICE_STATUS=""
    if [ -n "$SERVICES" ]; then
        IFS='|' read -ra SERVICE_ARRAY <<< "$SERVICES"
        for svc in "${SERVICE_ARRAY[@]}"; do
            svc=$(echo $svc | xargs)
            if [ -n "$svc" ]; then
                if command -v systemctl &>/dev/null; then
                    SVC_STATUS=$(systemctl is-active $svc 2>/dev/null)
                    if [ "$SVC_STATUS" == "active" ]; then
                        SERVICE_STATUS="${SERVICE_STATUS}  ${svc}: 运行中\n"
                    else
                        SERVICE_STATUS="${SERVICE_STATUS}  ${svc}: 未运行(${SVC_STATUS})\n"
                        if [ "$PROCESS_STATUS" == "OK" ]; then
                            PROCESS_STATUS="WARNING"
                        fi
                        PROCESS_WARNINGS="$PROCESS_WARNINGS, 服务${svc}未运行"
                    fi
                elif command -v service &>/dev/null; then
                    SVC_STATUS=$(service $svc status 2>/dev/null | head -1)
                    SERVICE_STATUS="${SERVICE_STATUS}  ${svc}: ${SVC_STATUS}\n"
                elif [ -f "/etc/init.d/$svc" ]; then
                    SVC_STATUS=$(/etc/init.d/$svc status 2>/dev/null | head -1)
                    SERVICE_STATUS="${SERVICE_STATUS}  ${svc}: ${SVC_STATUS}\n"
                else
                    SERVICE_STATUS="${SERVICE_STATUS}  ${svc}: 无法检测状态\n"
                fi
            fi
        done
    fi
    
    CRONTAB_CHECK=""
    if [ -f /var/spool/cron/root ]; then
        CRONTAB_CHECK=$(cat /var/spool/cron/root 2>/dev/null | grep -v "^#" | grep -v "^$")
    elif [ -f /etc/crontab ]; then
        CRONTAB_CHECK=$(cat /etc/crontab 2>/dev/null | grep -v "^#" | grep -v "^$")
    elif [ -d /etc/cron.d ]; then
        CRONTAB_CHECK=$(ls -la /etc/cron.d/ 2>/dev/null)
    fi
    
    UPTIME_CHECK=""
    if has_dep "uptime" && ! use_alt "uptime"; then
        UPTIME_CHECK=$(uptime -p 2>/dev/null || uptime)
    elif [ -f /proc/uptime ]; then
        UPTIME_SECONDS=$(cat /proc/uptime | awk '{print int($1)}')
        UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
        UPTIME_HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
        UPTIME_CHECK="up ${UPTIME_DAYS} days, ${UPTIME_HOURS} hours"
    fi
    
    result="进程与服务检查结果:\n"
    result="${result}  进程总数: ${PROCESS_TOTAL}\n"
    result="${result}  僵尸进程数: ${ZOMBIE_COUNT}\n"
    if [ -n "$SERVICE_STATUS" ]; then
        result="${result}  服务状态:\n${SERVICE_STATUS}"
    fi
    if [ -n "$CRONTAB_CHECK" ]; then
        result="${result}  定时任务:\n${CRONTAB_CHECK}\n"
    fi
    if [ -n "$UPTIME_CHECK" ]; then
        result="${result}  系统运行时间: ${UPTIME_CHECK}"
    fi
    
    echo "PROCESS_STATUS=$PROCESS_STATUS"
    echo "PROCESS_RUNNING=$PROCESS_RUNNING"
    echo "PROCESS_SLEEPING=$PROCESS_SLEEPING"
    echo "PROCESS_ZOMBIE=$ZOMBIE_COUNT"
    echo "PROCESS_TOTAL=$PROCESS_TOTAL"
    echo "ZOMBIE_COUNT=$ZOMBIE_COUNT"
    echo "PROCESS_RESULT=$result"
    echo "PROCESS_WARNINGS=$PROCESS_WARNINGS"
    echo "PROCESS_CRITICALS=$PROCESS_CRITICALS"
}
