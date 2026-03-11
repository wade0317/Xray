#!/bin/bash

# 初始化防火墙：确保 ufw 与 firewalld 二选一，优先 firewalld
# 规则：
#   - firewalld 已安装 + ufw 也安装 → 关闭 ufw，启用 firewalld
#   - 只有 firewalld 安装            → 确保 firewalld 已启用
#   - 只有 ufw 安装                  → 保持 ufw 现状（不强制启用，避免锁出）
#   - 都没有安装                     → 安装并启用 firewalld
fw_init() {
    local has_firewalld has_ufw
    command -v firewall-cmd &>/dev/null && has_firewalld=1
    command -v ufw &>/dev/null && has_ufw=1

    if [[ $has_firewalld && $has_ufw ]]; then
        # 两个都安装：关闭 ufw，使用 firewalld
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw disable &>/dev/null
            _yellow "检测到 ufw 和 firewalld 同时安装，已关闭 ufw，优先使用 firewalld"
        fi
        systemctl enable --now firewalld &>/dev/null
    elif [[ $has_firewalld ]]; then
        systemctl enable --now firewalld &>/dev/null
    elif [[ $has_ufw ]]; then
        # 只有 ufw，不强制启用（避免规则未配置时锁出 SSH）
        :
    else
        # 都没有安装：安装 firewalld
        _yellow "未检测到防火墙，正在安装 firewalld..."
        if command -v apt-get &>/dev/null; then
            apt-get install -y firewalld &>/dev/null
        elif command -v yum &>/dev/null; then
            yum install -y firewalld &>/dev/null
        fi
        systemctl enable --now firewalld &>/dev/null
        _green "firewalld 安装完成并已启用"
    fi
}

# 检测当前应使用的防火墙类型
# 优先级：firewalld（已安装即优先）> ufw（需已激活）
# 返回: firewalld / ufw / 空（无可用防火墙）
_fw_type() {
    if command -v firewall-cmd &>/dev/null; then
        echo "firewalld"
    elif ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "ufw"
    fi
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

    # 获取防火墙中已开放的端口列表
    local fw_ports=()
    case $fw in
    ufw)
        while IFS= read -r line; do
            local p
            p=$(echo "$line" | grep -oE '^[0-9]+/(tcp|udp)' | cut -d/ -f1)
            [[ $p ]] && fw_ports+=("$p")
        done < <(ufw status 2>/dev/null | grep -E "^[0-9]+" | awk '{print $1}')
        ;;
    firewalld)
        while IFS= read -r p; do
            fw_ports+=("${p%%/*}")
        done < <(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n')
        ;;
    esac

    # 关闭不再被任何配置使用的端口
    for fp in "${fw_ports[@]}"; do
        local still_used=0
        for ap in "${active_ports[@]}"; do
            [[ "$fp" == "$ap" ]] && { still_used=1; break; }
        done
        # 保留订阅端口
        [[ "$fp" == "$is_sub_port" ]] && continue
        [[ $still_used -eq 0 ]] && fw_del_port "$fp" tcp
    done
}

# 安装订阅服务时开放订阅端口
fw_allow_sub_port() {
    fw_add_port $is_sub_port tcp
}
