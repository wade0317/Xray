#!/bin/bash

# 持久化 iptables 规则（不依赖 iptables-persistent）
_fw_iptables_save() {
    if [[ -f /etc/iptables/rules.v4 ]]; then
        iptables-save > /etc/iptables/rules.v4
    elif [[ -f /etc/iptables.rules ]]; then
        iptables-save > /etc/iptables.rules
    else
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
    fi
}

# 清除 INPUT 链中位于 ufw 链之前的 REJECT/DROP 规则
# 避免云平台（OCI/AWS 等）预置规则屏蔽 ufw 生效
_fw_clean_legacy_rules() {
    command -v iptables &>/dev/null || return
    local nums
    nums=$(iptables -L INPUT --line-numbers -n 2>/dev/null | awk '
        /ufw-/ { exit }
        /REJECT|DROP/ { print $1 }
    ' | sort -rn)
    [[ ! $nums ]] && return
    local num
    for num in $nums; do
        iptables -D INPUT "$num" &>/dev/null
        _yellow "已清除冲突的 iptables 规则: INPUT 第 ${num} 条"
    done
    _fw_iptables_save
    _green "已持久化 iptables 规则"
}

# 检测当前应使用的防火墙类型
# 优先级：ufw > firewalld > iptables > 空（无防火墙）
# 返回: ufw / firewalld / iptables / 空
_fw_type() {
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        echo "firewalld"
    elif command -v iptables &>/dev/null && iptables -L INPUT -n 2>/dev/null | grep -qE "policy DROP|policy REJECT"; then
        echo "iptables"
    fi
}

# 初始化防火墙
# 优先检测已运行的防火墙，无则尝试安装，失败则提示后继续
# 始终返回 0，不阻断安装流程
fw_init() {
    local fw
    fw=$(_fw_type)
    case $fw in
    ufw)
        # ufw 已激活：清除云平台预置冲突规则，确保 ufw 正常生效
        _fw_clean_legacy_rules
        _green "防火墙: ufw 已激活"
        ;;
    firewalld)
        _green "防火墙: firewalld 已运行"
        ;;
    iptables)
        # iptables 已接管（如 OCI 默认环境）：清除 REJECT/DROP 规则，放行基础端口
        _yellow "防火墙: 检测到 iptables 直接管理，清除冲突规则..."
        _fw_clean_legacy_rules
        for _port in 22 80 443 ${is_sub_port}; do
            if ! iptables -C INPUT -p tcp --dport ${_port} -j ACCEPT &>/dev/null; then
                iptables -I INPUT -p tcp --dport ${_port} -j ACCEPT &>/dev/null
            fi
        done
        _fw_iptables_save
        _green "防火墙: iptables 基础端口已放行（22、80、443、${is_sub_port}）"
        ;;
    *)
        # 无防火墙：尝试安装
        if command -v apt-get &>/dev/null; then
            _yellow "正在安装 ufw..."
            apt-get install -y ufw &>/dev/null
            if command -v ufw &>/dev/null; then
                ufw allow 22/tcp &>/dev/null
                ufw allow 80/tcp &>/dev/null
                ufw allow 443/tcp &>/dev/null
                ufw allow ${is_sub_port}/tcp &>/dev/null
                ufw --force enable &>/dev/null
                if ufw status 2>/dev/null | grep -q "Status: active"; then
                    # ufw 启用后清除可能存在的 OCI 预置冲突规则
                    _fw_clean_legacy_rules
                    _green "ufw 安装并启用完成"
                else
                    _yellow "ufw 启用失败，请确保云平台安全组已放行所需端口（22、80、443、${is_sub_port}）"
                fi
            else
                _yellow "ufw 安装失败，请确保云平台安全组已放行所需端口（22、80、443、${is_sub_port}）"
            fi
        elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
            _yellow "正在安装 firewalld..."
            if command -v dnf &>/dev/null; then
                dnf install -y firewalld &>/dev/null
            else
                yum install -y firewalld &>/dev/null
            fi
            if command -v firewall-cmd &>/dev/null; then
                systemctl enable --now firewalld &>/dev/null
                if systemctl is-active --quiet firewalld; then
                    _green "firewalld 安装并启用完成"
                else
                    _yellow "firewalld 启用失败，请确保云平台安全组已放行所需端口（22、80、443、${is_sub_port}）"
                fi
            else
                _yellow "firewalld 安装失败，请确保云平台安全组已放行所需端口（22、80、443、${is_sub_port}）"
            fi
        else
            _yellow "未检测到系统防火墙，请确保云平台安全组已放行所需端口（22、80、443、${is_sub_port}）"
        fi
        ;;
    esac
    return 0
}

# 开放端口
# 用法: fw_add_port <port> [tcp|udp]
fw_add_port() {
    local port=$1 proto=${2:-tcp}
    [[ ! $port ]] && return
    local fw
    fw=$(_fw_type)
    [[ ! $fw ]] && return
    case $fw in
    ufw)
        ufw allow ${port}/${proto} &>/dev/null
        _green "防火墙已开放端口: ${port}/${proto} (ufw)"
        ;;
    firewalld)
        firewall-cmd --permanent --add-port=${port}/${proto} &>/dev/null
        firewall-cmd --reload &>/dev/null
        _green "防火墙已开放端口: ${port}/${proto} (firewalld)"
        ;;
    iptables)
        # 避免重复添加
        if ! iptables -C INPUT -p ${proto} --dport ${port} -j ACCEPT &>/dev/null; then
            iptables -I INPUT -p ${proto} --dport ${port} -j ACCEPT &>/dev/null
            _fw_iptables_save
        fi
        _green "防火墙已开放端口: ${port}/${proto} (iptables)"
        ;;
    esac
}

# 关闭端口
# 用法: fw_del_port <port> [tcp|udp]
fw_del_port() {
    local port=$1 proto=${2:-tcp}
    [[ ! $port ]] && return
    local fw
    fw=$(_fw_type)
    [[ ! $fw ]] && return
    case $fw in
    ufw)
        ufw delete allow ${port}/${proto} &>/dev/null
        _green "防火墙已关闭端口: ${port}/${proto} (ufw)"
        ;;
    firewalld)
        firewall-cmd --permanent --remove-port=${port}/${proto} &>/dev/null
        firewall-cmd --reload &>/dev/null
        _green "防火墙已关闭端口: ${port}/${proto} (firewalld)"
        ;;
    iptables)
        iptables -D INPUT -p ${proto} --dport ${port} -j ACCEPT &>/dev/null
        _fw_iptables_save
        _green "防火墙已关闭端口: ${port}/${proto} (iptables)"
        ;;
    esac
}

# add 后调用：根据协议类型开放对应端口
fw_allow_new() {
    [[ $is_gen || $is_no_auto_tls ]] && return
    if [[ $host ]]; then
        # TLS 协议由 Caddy 转发，开放 Caddy 监听的 HTTPS 端口
        fw_add_port $is_https_port tcp
    else
        # 直连协议，开放 Xray 监听端口
        fw_add_port $port tcp
        # KCP 同时需要 UDP
        [[ $net == 'kcp' ]] && fw_add_port $port udp
    fi
}

# del 后调用：检查端口是否还被其他配置使用，若无则关闭
# 注意：需在配置文件已删除后调用，以便准确统计剩余使用情况
fw_revoke_unused() {
    [[ ! $is_config_file ]] && return
    if [[ $host ]]; then
        # TLS 协议：检查是否还有其他 Caddy 站点配置
        local remaining
        remaining=$(ls "$is_caddy_conf"/*.conf 2>/dev/null | wc -l)
        [[ $remaining -gt 0 ]] && return
        fw_del_port $is_https_port tcp
    else
        # 直连协议：检查剩余配置是否还在使用该端口
        local used=0
        for f in "$is_conf_dir"/*.json; do
            [[ -f $f ]] || continue
            local p
            p=$(jq -r '.inbounds[0].port // empty' "$f" 2>/dev/null)
            [[ "$p" == "$port" ]] && { used=1; break; }
        done
        [[ $used -eq 1 ]] && return
        fw_del_port $port tcp
        [[ $net == 'kcp' ]] && fw_del_port $port udp
    fi
}

# ddel 批量删除后调用：扫描剩余配置，关闭所有不再被使用的直连端口
# TLS 端口（443）由 Caddy conf 文件数量决定
fw_sync_after_ddel() {
    local fw
    fw=$(_fw_type)
    [[ ! $fw ]] && return

    # 收集剩余配置中所有直连端口（无 host 的配置，listen 0.0.0.0）
    local active_ports=()
    for f in "$is_conf_dir"/*.json; do
        [[ -f $f ]] || continue
        # 跳过动态端口 link 文件
        [[ $f == *dynamic-port*-link* ]] && continue
        local p listen
        p=$(jq -r '.inbounds[0].port // empty' "$f" 2>/dev/null)
        listen=$(jq -r '.inbounds[0].listen // empty' "$f" 2>/dev/null)
        # 只收集直连（0.0.0.0）端口
        [[ $p && $listen == "0.0.0.0" ]] && active_ports+=("$p")
    done

    # 收集 Caddy 相关端口
    if [[ $is_caddy ]]; then
        local caddy_confs
        caddy_confs=$(ls "$is_caddy_conf"/*.conf 2>/dev/null | wc -l)
        [[ $caddy_confs -gt 0 ]] && active_ports+=("$is_https_port")
    fi

    # 获取防火墙中已开放的端口列表（格式: port/proto）
    local fw_ports=()
    case $fw in
    ufw)
        while IFS= read -r line; do
            local pp
            pp=$(echo "$line" | grep -oE '^[0-9]+/(tcp|udp)')
            [[ $pp ]] && fw_ports+=("$pp")
        done < <(ufw status 2>/dev/null | grep -E "^[0-9]+" | awk '{print $1}')
        ;;
    firewalld)
        while IFS= read -r pp; do
            [[ $pp ]] && fw_ports+=("$pp")
        done < <(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n')
        ;;
    iptables)
        while IFS= read -r line; do
            local p proto
            p=$(echo "$line" | grep -oE 'dpt:[0-9]+' | cut -d: -f2)
            proto=$(echo "$line" | grep -oE '(tcp|udp)' | head -1)
            [[ $p && $proto ]] && fw_ports+=("${p}/${proto}")
        done < <(iptables -L INPUT -n 2>/dev/null | grep -E "ACCEPT.*(tcp|udp).*dpt:")
        ;;
    esac

    # 关闭不再被任何配置使用的端口
    for fp in "${fw_ports[@]}"; do
        local port_num proto_str
        port_num="${fp%%/*}"
        proto_str="${fp##*/}"
        # 保留订阅端口和基础系统端口
        [[ "$port_num" == "$is_sub_port" || "$port_num" == "2096" ]] && continue
        [[ "$port_num" == "22" || "$port_num" == "80" || "$port_num" == "443" ]] && continue
        local still_used=0
        for ap in "${active_ports[@]}"; do
            [[ "$port_num" == "$ap" ]] && { still_used=1; break; }
        done
        [[ $still_used -eq 0 ]] && fw_del_port "$port_num" "$proto_str"
    done
}

# 安装订阅服务时开放订阅端口
fw_allow_sub_port() {
    fw_add_port $is_sub_port tcp
}
