#!/bin/bash

declare -A DEPS_REQUIRED
declare -A DEPS_OPTIONAL
declare -A DEPS_COMMANDS
declare -A DEPS_DESC
declare -A DEPS_ALT

DEPS_REQUIRED=(
    ["ssh"]="required"
    ["scp"]="required"
)

DEPS_OPTIONAL=(
    ["bc"]="cpu,memory,disk"
    ["mpstat"]="cpu"
    ["iostat"]="disk"
    ["lscpu"]="cpu"
    ["ss"]="network"
    ["netstat"]="network"
    ["free"]="memory"
    ["df"]="disk"
    ["find"]="disk"
    ["ps"]="process"
    ["top"]="cpu"
    ["awk"]="all"
    ["sed"]="all"
    ["grep"]="all"
    ["sshpass"]="password_login"
)

DEPS_COMMANDS=(
    ["bc"]="yum install -y bc || apt install -y bc"
    ["mpstat"]="yum install -y sysstat || apt install -y sysstat"
    ["iostat"]="yum install -y sysstat || apt install -y sysstat"
    ["lscpu"]="yum install -y util-linux || apt install -y util-linux"
    ["ss"]="yum install -y iproute || apt install -y iproute2"
    ["netstat"]="yum install -y net-tools || apt install -y net-tools"
    ["free"]="yum install -y procps-ng || apt install -y procps"
    ["df"]="yum install -y coreutils || apt install -y coreutils"
    ["find"]="yum install -y findutils || apt install -y findutils"
    ["ps"]="yum install -y procps-ng || apt install -y procps"
    ["top"]="yum install -y procps-ng || apt install -y procps"
    ["ping"]="yum install -y iputils || apt install -y iputils-ping"
    ["nslookup"]="yum install -y bind-utils || apt install -y dnsutils"
    ["ntpstat"]="yum install -y ntpstat || apt install -y ntpstat"
    ["timedatectl"]="yum install -y systemd || apt install -y systemd"
    ["firewall-cmd"]="yum install -y firewalld || apt install -y firewalld"
    ["iptables"]="yum install -y iptables || apt install -y iptables"
    ["mailx"]="yum install -y mailx || apt install -y mailutils"
    ["mutt"]="yum install -y mutt || apt install -y mutt"
    ["sshpass"]="yum install -y sshpass || apt install -y sshpass"
)

DEPS_DESC=(
    ["bc"]="高精度计算器，用于CPU/内存使用率计算"
    ["mpstat"]="CPU统计工具，用于获取精确CPU使用率"
    ["iostat"]="IO统计工具，用于磁盘IO分析"
    ["lscpu"]="CPU信息工具，用于获取CPU型号和核心数"
    ["ss"]="Socket统计工具，用于网络连接分析(替代netstat)"
    ["netstat"]="网络统计工具，用于网络连接分析(旧版)"
    ["free"]="内存统计工具，用于内存使用分析"
    ["df"]="磁盘统计工具，用于磁盘使用分析"
    ["find"]="文件查找工具，用于大文件扫描"
    ["ps"]="进程工具，用于进程分析"
    ["top"]="进程监控工具，用于CPU进程排序"
    ["ping"]="网络测试工具，用于网络连通性检查"
    ["nslookup"]="DNS查询工具，用于DNS状态检查"
    ["ntpstat"]="NTP状态工具，用于时间同步检查"
    ["timedatectl"]="时间设置工具，用于时间同步检查"
    ["firewall-cmd"]="防火墙工具，用于防火墙状态检查"
    ["iptables"]="防火墙工具，用于防火墙规则检查"
    ["mailx"]="邮件工具，用于发送巡检报告"
    ["mutt"]="邮件工具，用于发送巡检报告"
    ["sshpass"]="SSH密码登录工具，用于非免密登录服务器"
)

DEPS_ALT=(
    ["bc"]="使用awk进行计算，精度可能降低"
    ["mpstat"]="使用/proc/stat计算，精度略低"
    ["iostat"]="使用/proc/diskstats计算，功能受限"
    ["lscpu"]="使用/proc/cpuinfo获取基本信息"
    ["ss"]="使用netstat替代"
    ["netstat"]="使用/proc/net/tcp分析，功能受限"
    ["free"]="使用/proc/meminfo分析"
    ["df"]="使用/proc/mounts分析，功能受限"
    ["find"]="跳过大文件扫描功能"
    ["top"]="使用ps替代，无实时数据"
    ["ping"]="跳过网络连通性检查"
    ["nslookup"]="跳过DNS检查"
    ["ntpstat"]="使用timedatectl替代"
    ["timedatectl"]="检查/proc/uptime，无NTP状态"
    ["firewall-cmd"]="使用iptables替代"
    ["iptables"]="跳过防火墙检查"
    ["mailx"]="使用mutt替代"
    ["mutt"]="跳过邮件发送功能"
)

check_deps() {
    local mode=${1:-"interactive"}
    local missing_required=()
    local missing_optional=()
    local missing_info=()
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         依赖工具检查${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    for cmd in "${!DEPS_REQUIRED[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_required+=("$cmd")
        fi
    done
    
    if [ ${#missing_required[@]} -gt 0 ]; then
        echo -e "${RED}[错误] 缺少必需工具:${NC}"
        for cmd in "${missing_required[@]}"; do
            echo -e "  ${RED}✗${NC} $cmd - SSH远程执行必需"
        done
        echo ""
        echo -e "${RED}这些工具是必需的，无法继续执行。请安装后再运行脚本。${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[OK] 必需工具检查通过${NC}"
    echo ""
    
    for cmd in "${!DEPS_OPTIONAL[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_optional+=("$cmd")
            missing_info+=("$cmd|${DEPS_OPTIONAL[$cmd]}|${DEPS_COMMANDS[$cmd]:-无}|${DEPS_DESC[$cmd]:-未知}|${DEPS_ALT[$cmd]:-无替代方案}")
        fi
    done
    
    if [ ${#missing_optional[@]} -eq 0 ]; then
        echo -e "${GREEN}[OK] 所有可选工具都已安装${NC}"
        echo ""
        return 0
    fi
    
    echo -e "${YELLOW}[警告] 缺少以下可选工具:${NC}"
    echo ""
    printf "%-12s %-20s %s\n" "工具" "影响模块" "说明"
    echo "------------------------------------------------------------------------"
    for info in "${missing_info[@]}"; do
        IFS='|' read -r cmd modules install_cmd desc alt <<< "$info"
        printf "%-12s %-20s %s\n" "$cmd" "$modules" "$desc"
    done
    echo "------------------------------------------------------------------------"
    echo ""
    
    if [ "$mode" == "interactive" ]; then
        echo -e "${YELLOW}请选择处理方式:${NC}"
        echo ""
        echo "  ${GREEN}[1]${NC} 显示安装命令（由您手动安装后继续）"
        echo "  ${GREEN}[2]${NC} 使用替代方案继续执行（功能可能受限）"
        echo "  ${GREEN}[3]${NC} 显示详细说明（包含安装命令和替代方案）"
        echo "  ${GREEN}[4]${NC} 忽略并继续执行（跳过缺失工具的功能）"
        echo "  ${RED}[0]${NC} 退出脚本"
        echo ""
        
        while true; do
            read -p "请输入选项 [0-4]: " choice
            case $choice in
                1)
                    show_install_commands "${missing_optional[@]}"
                    echo ""
                    read -p "安装完成后按回车继续，或输入 q 退出: " confirm
                    if [ "$confirm" == "q" ] || [ "$confirm" == "Q" ]; then
                        return 1
                    fi
                    DEPS_USE_ALT=false
                    return 0
                    ;;
                2)
                    show_alt_solutions "${missing_info[@]}"
                    DEPS_USE_ALT=true
                    DEPS_MISSING=("${missing_optional[@]}")
                    return 0
                    ;;
                3)
                    show_detailed_info "${missing_info[@]}"
                    echo ""
                    read -p "请选择: [1]安装 [2]替代方案 [0]退出: " sub_choice
                    case $sub_choice in
                        1)
                            show_install_commands "${missing_optional[@]}"
                            read -p "安装完成后按回车继续: " confirm
                            DEPS_USE_ALT=false
                            return 0
                            ;;
                        2)
                            DEPS_USE_ALT=true
                            DEPS_MISSING=("${missing_optional[@]}")
                            return 0
                            ;;
                        0)
                            return 1
                            ;;
                        *)
                            echo -e "${RED}无效选项${NC}"
                            ;;
                    esac
                    ;;
                4)
                    echo -e "${YELLOW}忽略缺失工具，继续执行...${NC}"
                    DEPS_USE_ALT=true
                    DEPS_MISSING=("${missing_optional[@]}")
                    return 0
                    ;;
                0)
                    echo -e "${RED}退出脚本${NC}"
                    return 1
                    ;;
                *)
                    echo -e "${RED}无效选项，请重新输入${NC}"
                    ;;
            esac
        done
    else
        DEPS_USE_ALT=true
        DEPS_MISSING=("${missing_optional[@]}")
        return 0
    fi
}

show_install_commands() {
    local cmds=("$@")
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         安装命令${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}检测到系统类型: ${SYSTEM_TYPE:-未知}${NC}"
    echo ""
    
    for cmd in "${cmds[@]}"; do
        local install_cmd="${DEPS_COMMANDS[$cmd]}"
        if [ -n "$install_cmd" ]; then
            echo -e "${GREEN}# 安装 $cmd:${NC}"
            if [[ "$SYSTEM_TYPE" == *"CentOS"* ]] || [[ "$SYSTEM_TYPE" == *"Red Hat"* ]] || [[ "$SYSTEM_TYPE" == *"RHEL"* ]]; then
                echo "  yum install -y ${cmd%% *}"
            elif [[ "$SYSTEM_TYPE" == *"Ubuntu"* ]] || [[ "$SYSTEM_TYPE" == *"Debian"* ]]; then
                echo "  apt install -y ${cmd%% *}"
            else
                echo "  $install_cmd"
            fi
            echo ""
        fi
    done
    
    echo -e "${YELLOW}提示: 您也可以一次性安装所有缺失工具:${NC}"
    echo ""
    echo -e "${GREEN}# CentOS/RHEL:${NC}"
    local yum_pkgs=""
    for cmd in "${cmds[@]}"; do
        case $cmd in
            bc) yum_pkgs="$yum_pkgs bc" ;;
            mpstat|iostat) yum_pkgs="$yum_pkgs sysstat" ;;
            lscpu) yum_pkgs="$yum_pkgs util-linux" ;;
            ss) yum_pkgs="$yum_pkgs iproute" ;;
            netstat) yum_pkgs="$yum_pkgs net-tools" ;;
            free|ps|top) yum_pkgs="$yum_pkgs procps-ng" ;;
            find) yum_pkgs="$yum_pkgs findutils" ;;
            nslookup) yum_pkgs="$yum_pkgs bind-utils" ;;
        esac
    done
    yum_pkgs=$(echo $yum_pkgs | tr ' ' '\n' | sort -u | tr '\n' ' ')
    echo "  yum install -y$yum_pkgs"
    
    echo ""
    echo -e "${GREEN}# Ubuntu/Debian:${NC}"
    local apt_pkgs=""
    for cmd in "${cmds[@]}"; do
        case $cmd in
            bc) apt_pkgs="$apt_pkgs bc" ;;
            mpstat|iostat) apt_pkgs="$apt_pkgs sysstat" ;;
            lscpu) apt_pkgs="$apt_pkgs util-linux" ;;
            ss) apt_pkgs="$apt_pkgs iproute2" ;;
            netstat) apt_pkgs="$apt_pkgs net-tools" ;;
            free|ps|top) apt_pkgs="$apt_pkgs procps" ;;
            find) apt_pkgs="$apt_pkgs findutils" ;;
            ping) apt_pkgs="$apt_pkgs iputils-ping" ;;
            nslookup) apt_pkgs="$apt_pkgs dnsutils" ;;
        esac
    done
    apt_pkgs=$(echo $apt_pkgs | tr ' ' '\n' | sort -u | tr '\n' ' ')
    echo "  apt install -y$apt_pkgs"
}

show_alt_solutions() {
    local infos=("$@")
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         替代方案${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    for info in "${infos[@]}"; do
        IFS='|' read -r cmd modules install_cmd desc alt <<< "$info"
        echo -e "${YELLOW}$cmd:${NC}"
        echo "  影响: $modules"
        echo "  替代: $alt"
        echo ""
    done
    
    echo -e "${GREEN}将使用替代方案继续执行...${NC}"
}

show_detailed_info() {
    local infos=("$@")
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}         详细说明${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    for info in "${infos[@]}"; do
        IFS='|' read -r cmd modules install_cmd desc alt <<< "$info"
        echo -e "${GREEN}【$cmd】${NC}"
        echo "  说明: $desc"
        echo "  影响模块: $modules"
        echo -e "  ${YELLOW}安装命令:${NC}"
        echo "    CentOS/RHEL: yum install -y ${cmd%% *}"
        echo "    Ubuntu/Debian: apt install -y ${cmd%% *}"
        echo -e "  ${YELLOW}替代方案:${NC}"
        echo "    $alt"
        echo ""
        echo "  ----------------------------------------"
        echo ""
    done
}

check_single_dep() {
    local cmd=$1
    if command -v "$cmd" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

has_dep() {
    local cmd=$1
    if [[ " ${DEPS_MISSING[*]} " =~ " ${cmd} " ]]; then
        return 1
    fi
    return 0
}

use_alt() {
    local cmd=$1
    if [ "$DEPS_USE_ALT" == "true" ] && [[ " ${DEPS_MISSING[*]} " =~ " ${cmd} " ]]; then
        return 0
    fi
    return 1
}

get_alt_value() {
    local cmd=$1
    echo "${DEPS_ALT[$cmd]}"
}