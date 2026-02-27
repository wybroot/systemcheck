#!/bin/bash

check_security() {
    local result=""
    SEC_STATUS="OK"
    SEC_WARNINGS=""
    SEC_CRITICALS=""
    
    LOGIN_FAIL_COUNT=0
    LOGIN_SUCCESS_COUNT=0
    LOGIN_FAIL_USERS=0
    LOGIN_FAIL_IPS=""
    SELINUX_STATUS="unknown"
    
    if [ -f /var/log/secure ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/secure 2>/dev/null || true)
        LOGIN_SUCCESS_COUNT=$(grep -c "Accepted password" /var/log/secure 2>/dev/null || true)
        LOGIN_FAIL_USERS=$(grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $9}' | sort -u | wc -l || true)
        LOGIN_FAIL_IPS=$(grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -rn | head -10 | awk '{print $1 " (" $2 ")"}' || echo "")
    elif [ -f /var/log/auth.log ]; then
        LOGIN_FAIL_COUNT=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || true)
        LOGIN_SUCCESS_COUNT=$(grep -c "Accepted password" /var/log/auth.log 2>/dev/null || true)
        LOGIN_FAIL_USERS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $9}' | sort -u | wc -l || true)
        LOGIN_FAIL_IPS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -rn | head -10 | awk '{print $1 " (" $2 ")"}' || echo "")
    fi
    
    if command -v getenforce &>/dev/null; then
        SELINUX_STATUS=$(getenforce 2>/dev/null || echo "unknown")
    fi
    
    if [ "$LOGIN_FAIL_COUNT" -gt "$LOGIN_FAIL_CRITICAL" ] 2>/dev/null; then
        SEC_STATUS="CRITICAL"
        SEC_CRITICALS="登录失败次数${LOGIN_FAIL_COUNT}超过临界阈值${LOGIN_FAIL_CRITICAL}"
    elif [ "$LOGIN_FAIL_COUNT" -gt "$LOGIN_FAIL_WARNING" ] 2>/dev/null; then
        SEC_STATUS="WARNING"
        SEC_WARNINGS="登录失败次数${LOGIN_FAIL_COUNT}超过警告阈值${LOGIN_FAIL_WARNING}"
    fi
    
    ONLINE_USERS=""
    if has_dep "w" && command -v w &>/dev/null; then
        ONLINE_USERS=$(w 2>/dev/null | grep -v "USER" | head -10)
    elif [ -f /var/run/utmp ]; then
        ONLINE_USERS=$(who 2>/dev/null | head -10)
    fi
    
    USER_COUNT=0
    if [ -f /etc/passwd ]; then
        USER_COUNT=$(cat /etc/passwd 2>/dev/null | wc -l)
    fi
    
    SUDO_USERS=""
    if [ -f /etc/sudoers ]; then
        SUDO_USERS=$(grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | head -10)
    elif [ -d /etc/sudoers.d ]; then
        SUDO_USERS=$(cat /etc/sudoers.d/* 2>/dev/null | grep -v "^#" | grep -v "^$" | head -10)
    fi
    
    FIREWALL_STATUS=""
    if has_dep "firewall-cmd" && command -v firewall-cmd &>/dev/null; then
        FW_STATE=$(firewall-cmd --state 2>/dev/null)
        FIREWALL_STATUS="firewalld: ${FW_STATE}"
    elif has_dep "iptables" && command -v iptables &>/dev/null; then
        IPTABLES_COUNT=$(iptables -L -n 2>/dev/null | wc -l)
        FIREWALL_STATUS="iptables规则数: ${IPTABLES_COUNT}"
    elif has_dep "ufw" && command -v ufw &>/dev/null; then
        UFW_STATUS=$(ufw status 2>/dev/null | head -1)
        FIREWALL_STATUS="ufw: ${UFW_STATUS}"
    else
        FIREWALL_STATUS="无法检测防火墙状态(缺少相关命令)"
    fi
    
    SSH_CONFIG_CHECK=""
    if [ -f /etc/ssh/sshd_config ]; then
        SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        SSH_ROOT_LOGIN=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        SSH_PASSWORD_AUTH=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        
        SSH_CONFIG_CHECK="SSH端口: ${SSH_PORT:-22}\n"
        SSH_CONFIG_CHECK="${SSH_CONFIG_CHECK}Root登录: ${SSH_ROOT_LOGIN:-yes}\n"
        SSH_CONFIG_CHECK="${SSH_CONFIG_CHECK}密码认证: ${SSH_PASSWORD_AUTH:-yes}"
        
        if [ "$SSH_ROOT_LOGIN" == "yes" ] || [ -z "$SSH_ROOT_LOGIN" ]; then
            if [ "$SEC_STATUS" == "OK" ]; then
                SEC_STATUS="WARNING"
            fi
            SEC_WARNINGS="$SEC_WARNINGS, SSH允许Root登录"
        fi
        
        if [ "$SSH_PASSWORD_AUTH" == "yes" ] || [ -z "$SSH_PASSWORD_AUTH" ]; then
            SEC_WARNINGS="$SEC_WARNINGS, SSH允许密码认证"
        fi
    else
        SSH_CONFIG_CHECK="SSH配置文件不存在"
    fi
    
    LAST_LOGIN=""
    if has_dep "last" && command -v last &>/dev/null; then
        LAST_LOGIN=$(last -n 5 2>/dev/null | head -6)
    elif [ -f /var/log/wtmp ]; then
        LAST_LOGIN=$(last -f /var/log/wtmp -n 5 2>/dev/null | head -6)
    fi
    
    result="安全检查结果:\n"
    result="${result}  登录失败次数: ${LOGIN_FAIL_COUNT}\n"
    result="${result}  用户总数: ${USER_COUNT}\n"
    if [ -n "$ONLINE_USERS" ]; then
        result="${result}  在线用户:\n${ONLINE_USERS}\n"
    fi
    if [ -n "$LAST_LOGIN" ]; then
        result="${result}  最近登录:\n${LAST_LOGIN}\n"
    fi
    if [ -n "$FIREWALL_STATUS" ]; then
        result="${result}  防火墙状态: ${FIREWALL_STATUS}\n"
    fi
    if [ -n "$SSH_CONFIG_CHECK" ]; then
        result="${result}  SSH配置:\n${SSH_CONFIG_CHECK}"
    fi
    
    echo "SEC_STATUS=$SEC_STATUS"
    echo "LOGIN_FAIL_COUNT=$LOGIN_FAIL_COUNT"
    echo "LOGIN_SUCCESS_COUNT=$LOGIN_SUCCESS_COUNT"
    echo "LOGIN_FAIL_USERS=$LOGIN_FAIL_USERS"
    echo "LOGIN_FAIL_IPS=$LOGIN_FAIL_IPS"
    echo "FIREWALL_STATUS=$FIREWALL_STATUS"
    echo "SELINUX_STATUS=$SELINUX_STATUS"
    echo "USER_COUNT=$USER_COUNT"
    echo "SEC_RESULT=$result"
    echo "SEC_WARNINGS=$SEC_WARNINGS"
    echo "SEC_CRITICALS=$SEC_CRITICALS"
}
