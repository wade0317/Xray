caddy_config() {
    is_caddy_site_file=$is_caddy_conf/${host}.conf
    case $1 in
    new)
        mkdir -p $is_caddy_dir $is_caddy_dir/sites $is_caddy_conf
        cat >$is_caddyfile <<-EOF
# don't edit this file #
# for more info, see https://Wade0317.com/$is_core/caddy-auto-tls/
# 不要编辑这个文件 #
# 更多相关请阅读此文章: https://Wade0317.com/$is_core/caddy-auto-tls/
# https://caddyserver.com/docs/caddyfile/options
{
  admin off
  http_port $is_http_port
  https_port $is_https_port
}
import $is_caddy_conf/*.conf
import $is_caddy_dir/sites/*.conf
EOF
        ;;
    *ws*)
        cat >${is_caddy_site_file} <<<"
${host}:${is_https_port} {
    reverse_proxy ${path} 127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}"
        ;;
    *h2*)
        cat >${is_caddy_site_file} <<<"
${host}:${is_https_port} {
    reverse_proxy ${path} h2c://127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}"
        ;;
    *grpc*)
        cat >${is_caddy_site_file} <<<"
${host}:${is_https_port} {
    reverse_proxy /${path}/* h2c://127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}"
        ;;
    xhttp)
        cat >${is_caddy_site_file} <<<"
${host}:${is_https_port} {
    reverse_proxy ${path}/* h2c://127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}"
        ;;
    proxy)
        
        cat >${is_caddy_site_file}.add <<<"
reverse_proxy https://$proxy_site {
        header_up Host {upstream_hostport}
}"
        ;;
    esac
    [[ $1 != "new" && $1 != 'proxy' ]] && {
        if [[ ! -f ${is_caddy_site_file}.add ]]; then
            echo "# see https://Wade0317.com/$is_core/caddy-auto-tls/" >${is_caddy_site_file}.add
            # 订阅已初始化时，同步将订阅路径写入新域名
            [[ $is_sub_token ]] && _sub_add_handle_to_conf_add ${is_caddy_site_file}.add
        fi
    }
}

# 向指定 .conf.add 文件追加订阅路径 handle 块（幂等，避免重复写入）
_sub_add_handle_to_conf_add() {
    local conf_add=$1
    [[ ! -f $conf_add ]] && return
    grep -q '/sub/' $conf_add && return
    cat >>$conf_add <<-EOF

handle /sub/* {
    root * ${is_sub_dir}
    uri strip_prefix /sub
    file_server
    header Access-Control-Allow-Origin "*"
}
EOF
}

subscribe_caddy_config() {
    mkdir -p $is_caddy_dir/sites

    # 始终保留独立端口（无域名 / 直接 IP 访问的备用方案）
    cat >$is_sub_caddy_conf <<-EOF
:${is_sub_port} {
    root * ${is_sub_dir}
    file_server
    header Access-Control-Allow-Origin "*"
}
EOF

    # 同时将订阅路径注入所有已存在的域名配置
    for conf_add in $is_caddy_conf/*.conf.add; do
        [[ -f $conf_add ]] && _sub_add_handle_to_conf_add $conf_add
    done

    # 确保防火墙开放订阅端口 2096
    load firewall.sh
    fw_add_port $is_sub_port tcp
}
