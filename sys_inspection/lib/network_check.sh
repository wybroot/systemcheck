#!/bin/bash

check_network() {
    local result=""
    local status="OK"
    local warnings=""
    local criticals=""
    
    CONNECTION_COUNT=0
    TIME_WAIT_COUNT=0
    
    if has_dep "ss" && ! use_alt "ss"; then
        CONNECTION_COUNT=$(ss -s 2>/dev/null | grep "estab" | awk '{print $2}' | head -1)
        CONNECTION_COUNT=${CONNECTION_COUNT:-0}
        TCP_STATES=$(ss -tan 2>/dev/null | awk 'NR>1 {count[$1]++} END {for(state in count) print state": "count[state]}')
        TIME_WAIT_COUNT=$(ss -tan 2>/dev/null | grep -c "TIME-WAIT" || echo 0)
    elif has_dep "netstat" && ! use_alt "netstat"; then
        CONNECTION_COUNT=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
        TCP_STATES=$(netstat -tan 2>/dev/null | awk 'NR>2 {count[$6]++} END {for(state in count) print state": "count[state]}')
        TIME_WAIT_COUNT=$(netstat -tan 2>/dev/null | grep -c TIME_WAIT || echo 0)
    else
        if [ -f /proc/net/tcp ]; then
            CONNECTION_COUNT=$(grep -c "01" /proc/net/tcp 2>/dev/null || echo 0)
            TCP_STATES="连接状态统计需要ss或netstat命令"
        else
            TCP_STATES="无法获取TCP状态(缺少ss/netstat命令)"
        fi
    fi
    
    CONNECTION_COUNT=${CONNECTION_COUNT:-0}
    TIME_WAIT_COUNT=${TIME_WAIT_COUNT:-0}
    
    if [ "$CONNECTION_COUNT" -gt "$CONNECTION_CRITICAL" ] 2>/dev/null; then
        status="CRITICAL"
        criticals="网络连接数${CONNECTION_COUNT}超过临界阈值${CONNECTION_CRITICAL}"
    elif [ "$CONNECTION_COUNT" -gt "$CONNECTION_WARNING" ] 2>/dev/null; then
        status="WARNING"
        warnings="网络连接数${CONNECTION_COUNT}超过警告阈值${CONNECTION_WARNING}"
    fi
    
    if [ "$TIME_WAIT_COUNT" -gt "$TIME_WAIT_WARNING" ] 2>/dev/null; then
        [ "$status" == "OK" ] && status="WARNING"
        warnings="$warnings, TIME_WAIT连接数${TIME_WAIT_COUNT}过多"
    fi
    
    LISTEN_PORTS=""
    if has_dep "ss" && ! use_alt "ss"; then
        LISTEN_PORTS=$(ss -tlnp 2>/dev/null | grep LISTEN)
    elif has_dep "netstat" && ! use_alt "netstat"; then
        LISTEN_PORTS=$(netstat -tlnp 2>/dev/null | grep LISTEN)
    else
        LISTEN_PORTS="无法获取监听端口(缺少ss/netstat命令)"
    fi
    
    NETWORK_INTERFACES=""
    if command -v ip &>/dev/null; then
        NETWORK_INTERFACES=$(ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet " | head -20)
    elif command -v ifconfig &>/dev/null; then
        NETWORK_INTERFACES=$(ifconfig 2>/dev/null | grep -E "^[a-z]|inet " | head -20)
    else
        if [ -f /proc/net/dev ]; then
            NETWORK_INTERFACES=$(cat /proc/net/dev 2>/dev/null | tail -n +3)
        fi
    fi
    
    GATEWAY_PING=""
    PACKET_LOSS=""
    DEFAULT_GW=""
    
    if command -v ip &>/dev/null; then
        DEFAULT_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    elif command -v route &>/dev/null; then
        DEFAULT_GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print $2}' | head -1)
    fi
    
    if [ -n "$DEFAULT_GW" ]; then
        if has_dep "ping" && ! use_alt "ping"; then
            PING_RESULT=$(ping -c 3 -W 2 $DEFAULT_GW 2>/dev/null)
            PACKET_LOSS=$(echo "$PING_RESULT" | grep "packet loss" | awk '{print $6}' | tr -d '%')
            
            if [ -n "$PACKET_LOSS" ]; then
                GATEWAY_PING="网关${DEFAULT_GW}丢包率: ${PACKET_LOSS}%"
                
                if [ "$PACKET_LOSS" -gt "$PACKET_LOSS_CRITICAL" ] 2>/dev/null; then
                    [ "$status" != "CRITICAL" ] && status="CRITICAL"
                    criticals="$criticals, 网关丢包率${PACKET_LOSS}%过高"
                elif [ "$PACKET_LOSS" -gt "$PACKET_LOSS_WARNING" ] 2>/dev/null; then
                    [ "$status" == "OK" ] && status="WARNING"
                    warnings="$warnings, 网关丢包率${PACKET_LOSS}%偏高"
                fi
            fi
        else
            GATEWAY_PING="网关: ${DEFAULT_GW} (无法ping测试)"
        fi
    fi
    
    DNS_CHECK=""
    if [ -f /etc/resolv.conf ]; then
        DNS_SERVERS=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}')
        
        if [ -n "$DNS_SERVERS" ]; then
            for dns in $DNS_SERVERS; do
                if has_dep "nslookup" && ! use_alt "nslookup"; then
                    DNS_TEST=$(nslookup baidu.com $dns 2>/dev/null | grep -c "Address" || echo 0)
                    if [ "$DNS_TEST" -gt 0 ]; then
                        DNS_CHECK="${DNS_CHECK}DNS ${dns}: 正常\n"
                    else
                        DNS_CHECK="${DNS_CHECK}DNS ${dns}: 异常\n"
                    fi
                else
                    DNS_CHECK="${DNS_CHECK}DNS ${dns}: (无法测试)\n"
                fi
            done
        fi
    fi
    
    result="网络检查结果:\n"
    result="${result}  网络连接数: ${CONNECTION_COUNT}\n"
    result="${result}  TIME_WAIT连接: ${TIME_WAIT_COUNT}\n"
    if [ -n "$TCP_STATES" ]; then
        result="${result}  TCP连接状态:\n${TCP_STATES}\n"
    fi
    if [ -n "$GATEWAY_PING" ]; then
        result="${result}  网络连通性: ${GATEWAY_PING}\n"
    fi
    if [ -n "$DNS_CHECK" ]; then
        result="${result}  DNS状态:\n${DNS_CHECK}"
    fi
    
    echo "NET_STATUS=$status"
    echo "CONNECTION_COUNT=$CONNECTION_COUNT"
    echo "TIME_WAIT_COUNT=$TIME_WAIT_COUNT"
    echo "NET_RESULT=$result"
    echo "NET_WARNINGS=$warnings"
    echo "NET_CRITICALS=$criticals"
}