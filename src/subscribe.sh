#!/bin/bash

# 初始化订阅目录和 Token（安装时调用一次）
init_subscribe() {
    _mkdir $is_sub_dir
    is_sub_token=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
    echo $is_sub_token >$is_sub_token_file
    chmod 600 $is_sub_token_file
    _mkdir $is_sub_dir/$is_sub_token
}

# 显示订阅链接
# 有 Caddy 域名时优先显示 HTTPS 域名链接，同时保留 IP:2096 备用
show_sub_link() {
    [[ ! $is_sub_token ]] && return
    [[ ! $is_addr ]] && get addr

    msg ""
    msg "------------- 订阅链接 -------------"

    # 有域名：显示 HTTPS 域名链接（遍历所有已配置域名）
    local has_domain=0
    if [[ $is_caddy ]]; then
        for conf in $is_caddy_conf/*.conf; do
            [[ -f $conf ]] || continue
            local domain
            domain=$(basename "$conf" .conf)
            local base="https://${domain}:${is_https_port}/sub/${is_sub_token}"
            msg ""
            msg "Clash (Mihomo) 订阅地址 - 推荐:"
            msg ""
            msg "  ${base}/clash.yaml"
            msg ""
            msg "Sing-box 订阅地址:"
            msg ""
            msg "  ${base}/singbox.json"
            msg ""
            msg "V2ray/NekoBox 通用订阅地址 (Base64):"
            msg ""
            msg "  ${base}/base64.txt"
            has_domain=1
            break
        done
    fi

    # 始终显示 IP:端口链接
    local base_ip="http://${is_addr}:${is_sub_port}/${is_sub_token}"
    [[ $has_domain -eq 1 ]] && msg "---"
    msg ""
    msg "Clash (Mihomo) 订阅地址 - 推荐:"
    msg ""
    msg "  ${base_ip}/clash.yaml"
    msg ""
    msg "Sing-box 订阅地址:"
    msg ""
    msg "  ${base_ip}/singbox.json"
    msg ""
    msg "V2ray/NekoBox 通用订阅地址 (Base64):"
    msg ""
    msg "  ${base_ip}/base64.txt"
    msg ""

    msg "------------------------------------"
}

# 从当前 info 变量生成分享 URL
_sub_get_url() {
    local tag="$1"
    local url=""
    case $net in
    tcp | kcp | quic)
        if [[ $is_reality ]]; then
            url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$is_servername&pbk=$is_public_key&fp=chrome#${tag}"
        else
            local vmess_json
            vmess_json=$(jq -c '{v:2,ps:"'${tag}'",add:"'$is_addr'",port:"'$port'",id:"'$uuid'",aid:"0",net:"'$net'",type:"'$header_type'",path:"'$kcp_seed'"}' <<<{})
            url="vmess://$(echo -n $vmess_json | base64 -w 0)"
        fi
        ;;
    ss)
        url="ss://$(echo -n ${ss_method}:${ss_password} | base64 -w 0)@${is_addr}:${port}#${tag}"
        ;;
    ws | h2 | grpc | xhttp)
        local url_path=path
        local p=$path
        [[ $net == 'grpc' ]] && { url_path=serviceName; p=$(sed 's#/##g' <<<$p); }
        if [[ $is_protocol == 'vmess' ]]; then
            local vmess_json
            vmess_json=$(jq -c '{v:2,ps:"'${tag}'",add:"'$is_addr'",port:"'$is_https_port'",id:"'$uuid'",aid:"0",net:"'$net'",host:"'$host'",path:"'$p'",tls:"tls"}' <<<{})
            url="vmess://$(echo -n $vmess_json | base64 -w 0)"
        else
            local cred=$uuid
            [[ $is_trojan ]] && cred=$trojan_password
            url="${is_protocol}://${cred}@${host}:${is_https_port}?encryption=none&security=tls&type=${net}&host=${host}&${url_path}=$(sed 's#/#%2F#g' <<<$p)#${tag}"
        fi
        ;;
    socks)
        url="socks://$(echo -n ${is_socks_user}:${is_socks_pass} | base64 -w 0)@${is_addr}:${port}#${tag}"
        ;;
    esac
    echo "$url"
}

# 生成 sing-box outbound JSON 片段
_sub_singbox_outbound() {
    local tag="$1"
    local out=""
    case $net in
    tcp | kcp | quic)
        if [[ $is_reality ]]; then
            out=$(jq -nc \
                --arg tag "$tag" \
                --arg server "$is_addr" \
                --argjson port "$port" \
                --arg uuid "$uuid" \
                --arg sni "$is_servername" \
                --arg pubkey "$is_public_key" \
                '{type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid,flow:"xtls-rprx-vision",
                  tls:{enabled:true,server_name:$sni,
                       utls:{enabled:true,fingerprint:"chrome"},
                       reality:{enabled:true,public_key:$pubkey}}}')
        else
            out=$(jq -nc \
                --arg tag "$tag" \
                --arg server "$is_addr" \
                --argjson port "$port" \
                --arg uuid "$uuid" \
                '{type:"vmess",tag:$tag,server:$server,server_port:$port,uuid:$uuid,security:"auto"}')
        fi
        ;;
    ss)
        out=$(jq -nc \
            --arg tag "$tag" \
            --arg server "$is_addr" \
            --argjson port "$port" \
            --arg method "$ss_method" \
            --arg password "$ss_password" \
            '{type:"shadowsocks",tag:$tag,server:$server,server_port:$port,method:$method,password:$password}')
        ;;
    ws | h2 | grpc | xhttp)
        local proto=$is_protocol
        local cred_key="uuid"
        local cred_val=$uuid
        [[ $is_trojan ]] && { proto=trojan; cred_key="password"; cred_val=$trojan_password; }
        local transport=""
        local p=$path
        case $net in
        ws)
            transport=$(jq -nc --arg path "$p" --arg host "$host" \
                '{type:"ws",path:$path,headers:{Host:$host}}')
            ;;
        grpc)
            p=$(sed 's#/##g' <<<$p)
            transport=$(jq -nc --arg svc "$p" '{type:"grpc",service_name:$svc}')
            ;;
        xhttp | h2)
            transport=$(jq -nc --arg path "$p" --arg host "$host" \
                '{type:"http",path:$path,host:[$host]}')
            ;;
        esac
        out=$(jq -nc \
            --arg type "$proto" \
            --arg tag "$tag" \
            --arg server "$host" \
            --argjson port "$is_https_port" \
            --arg cred_key "$cred_key" \
            --arg cred_val "$cred_val" \
            --arg sni "$host" \
            --argjson transport "$transport" \
            '{type:$type,tag:$tag,server:$server,server_port:$port,
              ($cred_key):$cred_val,
              tls:{enabled:true,server_name:$sni},
              transport:$transport}')
        ;;
    socks)
        out=$(jq -nc \
            --arg tag "$tag" \
            --arg server "$is_addr" \
            --argjson port "$port" \
            --arg user "$is_socks_user" \
            --arg pass "$is_socks_pass" \
            '{type:"socks",tag:$tag,server:$server,server_port:$port,
              username:$user,password:$pass,version:"5"}')
        ;;
    esac
    echo "$out"
}

# 生成 Mihomo proxy YAML 片段
_sub_mihomo_proxy() {
    local tag="$1"
    case $net in
    tcp | kcp | quic)
        if [[ $is_reality ]]; then
            cat <<EOF
  - name: "${tag}"
    type: vless
    server: ${is_addr}
    port: ${port}
    uuid: ${uuid}
    flow: xtls-rprx-vision
    tls: true
    reality-opts:
      public-key: ${is_public_key}
      short-id: ""
    client-fingerprint: chrome
    servername: ${is_servername}
    network: tcp
EOF
        else
            cat <<EOF
  - name: "${tag}"
    type: vmess
    server: ${is_addr}
    port: ${port}
    uuid: ${uuid}
    alterId: 0
    cipher: auto
EOF
        fi
        ;;
    ss)
        cat <<EOF
  - name: "${tag}"
    type: ss
    server: ${is_addr}
    port: ${port}
    cipher: ${ss_method}
    password: ${ss_password}
EOF
        ;;
    ws | h2 | grpc | xhttp)
        local proto=$is_protocol
        [[ $is_trojan ]] && proto=trojan
        local cred_line=""
        if [[ $proto == "trojan" ]]; then
            cred_line="    password: ${trojan_password}"
        else
            cred_line="    uuid: ${uuid}"
        fi
        local transport_opts=""
        local p=$path
        case $net in
        ws)
            transport_opts=$(cat <<EOF
    network: ws
    ws-opts:
      path: ${p}
      headers:
        Host: ${host}
EOF
)
            ;;
        grpc)
            p=$(sed 's#/##g' <<<$p)
            transport_opts=$(cat <<EOF
    network: grpc
    grpc-opts:
      grpc-service-name: ${p}
EOF
)
            ;;
        xhttp | h2)
            transport_opts=$(cat <<EOF
    network: http
    http-opts:
      path:
        - ${p}
      headers:
        Host:
          - ${host}
EOF
)
            ;;
        esac
        cat <<EOF
  - name: "${tag}"
    type: ${proto}
    server: ${host}
    port: ${is_https_port}
${cred_line}
    tls: true
    servername: ${host}
${transport_opts}
EOF
        ;;
    socks)
        cat <<EOF
  - name: "${tag}"
    type: socks5
    server: ${is_addr}
    port: ${port}
    username: ${is_socks_user}
    password: ${is_socks_pass}
EOF
        ;;
    esac
}

# 基于 sing-box 模板生成完整配置（替换 outbounds）
_gen_singbox_config() {
    local outs="$1"    # JSON 数组元素，逗号分隔
    local tags="$2"    # "tag1","tag2","tag3"
    local first_tag
    first_tag=$(echo "$tags" | sed 's/,.*//' | tr -d '"')

    # 构建 tag 数组（jq array）
    local tags_arr
    tags_arr=$(echo "$tags" | jq -Rc 'split(",") | map(ltrimstr("\"") | rtrimstr("\"")) | map(select(. != ""))')

    # sing-box 1.11.0+ 废弃了 block/dns 特殊 outbound，改用 route rules 的 action 字段
    jq --argjson nodes "[${outs:-}]" \
       --argjson tag_arr "$tags_arr" \
       --arg default_tag "$first_tag" \
       '.outbounds = [
           {"type":"direct","tag":"direct"},
           {"type":"selector","tag":"proxy",
            "outbounds": $tag_arr,
            "default": $default_tag}
       ] + $nodes' \
       "$is_tmpl_dir/sing-box-vpn.json"
}

# 基于 clash 模板生成完整配置（替换 proxies + proxy-groups）
_gen_mihomo_config() {
    local proxies="$1"
    local names="$2"   # "      - \"tag\"\n" 格式

    # 模板头部（proxies: 之前）
    awk '/^proxies:/{exit} {print}' "$is_tmpl_dir/clash-vpn.yaml"

    # 动态 proxies 节
    printf "proxies:\n"
    printf "%s" "$proxies"

    # 动态 proxy-groups 节
    printf "\nproxy-groups:\n"
    printf "  - name: \"proxy\"\n"
    printf "    type: select\n"
    printf "    proxies:\n"
    printf "      - \"auto\"\n"
    printf "%b" "$names"
    printf "      - DIRECT\n\n"
    printf "  - name: \"auto\"\n"
    printf "    type: url-test\n"
    printf "    proxies:\n"
    printf "%b" "$names"
    printf "    url: \"http://cp.cloudflare.com/\"\n"
    printf "    interval: 300\n"
    printf "    tolerance: 50\n\n"

    # 模板尾部（rule-providers: 及之后）
    awk '/^rule-providers:/{found=1} found{print}' "$is_tmpl_dir/clash-vpn.yaml"
}

# 主入口：遍历所有节点，生成三种订阅文件
gen_subscribe() {
    [[ ! $is_sub_token ]] && return
    [[ ! -d $is_conf_dir ]] && return
    _mkdir "$is_sub_dir/$is_sub_token"

    local urls="" sb_outbounds="" sb_tags="" mh_proxies="" mh_names=""
    local saved_dont_auto_exit=$is_dont_auto_exit
    is_dont_auto_exit=1

    for f in $(ls "$is_conf_dir" 2>/dev/null | grep '\.json$' | grep -v 'dynamic-port.*-link'); do
        # 清理上次循环残留变量
        unset is_protocol port uuid host net path trojan_password ss_method \
              ss_password is_socks_user is_socks_pass is_reality is_servername \
              is_public_key is_https_port is_addr is_config_file is_dynamic_port \
              header_type kcp_seed is_trojan is_no_auto_tls
        is_config_file=$f
        get info "$f"
        [[ ! $is_protocol || $net == 'door' || $net == 'http' ]] && continue

        local tag
        tag=$(echo "$f" | sed 's/\.json$//')

        local url
        url=$(_sub_get_url "$tag")
        [[ $url ]] && urls+="${url}\n"

        local sb
        sb=$(_sub_singbox_outbound "$tag")
        [[ $sb ]] && {
            sb_outbounds+="${sb_outbounds:+,}${sb}"
            sb_tags+="${sb_tags:+,}\"${tag}\""
        }

        local mp
        mp=$(_sub_mihomo_proxy "$tag")
        [[ $mp ]] && {
            mh_proxies+="${mp}"$'\n'
            mh_names+="      - \"${tag}\"\n"
        }
    done

    is_dont_auto_exit=$saved_dont_auto_exit

    local _sub_out="$is_sub_dir/$is_sub_token"

    # 写 base64 通用订阅
    printf "%b" "$urls" | base64 -w 0 >"$_sub_out/base64.txt"

    # 写 sing-box 配置（sing-box 1.11.0+ 不再使用 block/dns-out 特殊 outbound）
    if [[ $sb_outbounds ]]; then
        _gen_singbox_config "$sb_outbounds" "$sb_tags" >"$_sub_out/singbox.json"
    else
        if [[ -f "$is_tmpl_dir/sing-box-vpn.json" ]]; then
            jq '.outbounds = [{"type":"direct","tag":"direct"}]' \
                "$is_tmpl_dir/sing-box-vpn.json" >"$_sub_out/singbox.json"
        else
            echo '{"outbounds":[{"type":"direct","tag":"direct"}]}' >"$_sub_out/singbox.json"
        fi
    fi
    local _sb_size
    _sb_size=$(wc -c <"$_sub_out/singbox.json" 2>/dev/null || echo 0)
    [[ $_sb_size -lt 10 ]] && echo "  警告: singbox.json 内容异常，请检查模板: $is_tmpl_dir/sing-box-vpn.json"

    # 写 Mihomo 配置
    _gen_mihomo_config "$mh_proxies" "$mh_names" >"$_sub_out/clash.yaml"
}
