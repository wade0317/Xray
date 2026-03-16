#!/bin/bash

author=wade0317
# github=https://github.com/wade0317/xray

# bash fonts colors
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

_red() { echo -e ${red}$@${none}; }
_blue() { echo -e ${blue}$@${none}; }
_cyan() { echo -e ${cyan}$@${none}; }
_green() { echo -e ${green}$@${none}; }
_yellow() { echo -e ${yellow}$@${none}; }
_magenta() { echo -e ${magenta}$@${none}; }
_red_bg() { echo -e "\e[41m$@${none}"; }

_rm() {
    rm -rf "$@"
}
_cp() {
    cp -rf "$@"
}
_sed() {
    sed -i "$@"
}
_mkdir() {
    mkdir -p "$@"
}

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() {
    echo -e "\n$is_err $@\n"
    [[ $is_dont_auto_exit ]] && return
    exit 1
}

warn() {
    echo -e "\n$is_warn $@\n"
}

restart_service_checked() {
    local service_name=$1
    local service_label=$2
    (
        if ! systemctl restart "$service_name" &>/dev/null; then
            warn "${service_label} 自动重启失败，请检查: systemctl status ${service_name}"
        fi
    ) &
}

# load bash script.
load() {
    . $is_sh_dir/src/$1
}

# wget add --no-check-certificate
_wget() {
    # [[ $proxy ]] && export https_proxy=$proxy
    wget --no-check-certificate "$@"
}

# yum or apt-get
cmd=$(type -P apt-get || type -P yum)

# x64
case $(arch) in
amd64 | x86_64)
    is_core_arch="64"
    caddy_arch="amd64"
    ;;
*aarch64* | *armv8*)
    is_core_arch="arm64-v8a"
    caddy_arch="arm64"
    ;;
*)
    err "此脚本仅支持 64 位系统..."
    ;;
esac

is_core=xray
is_core_name=Xray
is_core_dir=/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=xtls/$is_core-core
is_conf_dir=$is_core_dir/conf
is_log_dir=/var/log/$is_core
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_sh_repo=wade0317/Xray
is_pkg="wget unzip jq qrencode"
is_config_json=$is_core_dir/config.json
is_caddy_bin=/usr/local/bin/caddy
is_caddy_dir=/etc/caddy
is_caddy_repo=caddyserver/caddy
is_caddyfile=$is_caddy_dir/Caddyfile
is_caddy_conf=$is_caddy_dir/$author
is_caddy_service=$(systemctl list-units --full -all | grep caddy.service)
is_http_port=80
is_https_port=443
is_sub_dir=$is_core_dir/subscribe
is_sub_token_file=$is_sub_dir/token
is_sub_port=2096
is_sub_caddy_conf=$is_caddy_dir/sites/subscribe.conf
is_tmpl_dir=$is_sh_dir/template
is_service_ver_file=$is_core_dir/.service_ver

# core ver
is_core_ver=$($is_core_bin version | head -n1 | cut -d " " -f1-2)

if [[ $(pgrep -f $is_core_bin) ]]; then
    is_core_status=$(_green running)
else
    is_core_status=$(_red_bg stopped)
    is_core_stop=1
fi
if [[ -f $is_caddy_bin && -d $is_caddy_dir && $is_caddy_service ]]; then
    if [[ $(pgrep -f $is_caddy_bin) ]]; then
        is_caddy_status=$(_green running)
    else
        is_caddy_status=$(_red_bg stopped)
        is_caddy_stop=1
    fi
fi

if [[ "$(cat "$is_service_ver_file" 2>/dev/null)" != "$is_sh_ver" ]]; then
    load systemd.sh
    [[ -f /lib/systemd/system/$is_core.service ]] && {
        install_service $is_core
        [[ ! $is_core_stop ]] && restart_service_checked "$is_core" "$is_core_name"
    }
    install_logrotate
    if [[ -f $is_caddy_bin && -d $is_caddy_dir && $is_caddy_service ]]; then
        install_service caddy
        [[ ! $is_caddy_stop ]] && restart_service_checked caddy Caddy
    fi
    echo "$is_sh_ver" >"$is_service_ver_file"
fi
if [[ -f $is_caddy_bin && -d $is_caddy_dir && $is_caddy_service ]]; then
    is_caddy=1
    is_caddy_ver=$($is_caddy_bin version | head -n1 | cut -d " " -f1)
    is_tmp_http_port=$(grep -E '^ {2,}http_port|^http_port' $is_caddyfile | grep -E -o [0-9]+)
    is_tmp_https_port=$(grep -E '^ {2,}https_port|^https_port' $is_caddyfile | grep -E -o [0-9]+)
    [[ $is_tmp_http_port ]] && is_http_port=$is_tmp_http_port
    [[ $is_tmp_https_port ]] && is_https_port=$is_tmp_https_port
fi

[[ -f $is_sub_token_file ]] && is_sub_token=$(cat $is_sub_token_file)

load core.sh
[[ ! $args ]] && args=main
main $args
