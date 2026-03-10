get_latest_version() {
    local _repo
    case $1 in
    core)
        name=$is_core_name
        _repo=$is_core_repo
        ;;
    sh)
        name="$is_core_name 脚本"
        _repo=$is_sh_repo
        ;;
    caddy)
        name="Caddy"
        _repo=$is_caddy_repo
        ;;
    esac

    # 方法1: GitHub API
    latest_ver=$(_wget -qO- "https://api.github.com/repos/${_repo}/releases/latest?v=$RANDOM" | grep tag_name | grep -E -o 'v([0-9.]+)')
    # 方法2: releases 页面 Location header
    [[ ! $latest_ver ]] && {
        latest_ver=$(wget -S -q "https://github.com/${_repo}/releases/latest" -O /dev/null 2>&1 | grep -i 'Location:' | grep -oE 'v[0-9.]+(\.[0-9]+)*' | head -1)
    }
    # 方法3: 硬编码兜底版本
    [[ ! $latest_ver ]] && {
        case $1 in
        caddy) latest_ver="v2.11.2" ;;
        esac
    }

    [[ ! $latest_ver ]] && {
        err "获取 ${name} 最新版本失败."
    }
    unset name _repo
}
download() {
    latest_ver=$2
    [[ ! $latest_ver && $1 != 'dat' ]] && get_latest_version $1
    # tmp dir
    tmpdir=$(mktemp -u)
    [[ ! $tmpdir ]] && {
        tmpdir=/tmp/tmp-$RANDOM
    }
    mkdir -p $tmpdir
    case $1 in
    core)
        name=$is_core_name
        tmpfile=$tmpdir/$is_core.zip
        link="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${is_core}-linux-${is_core_arch}.zip"
        download_file
        unzip -qo $tmpfile -d $is_core_dir/bin
        chmod +x $is_core_bin
        ;;
    sh)
        name="$is_core_name 脚本"
        tmpfile=$tmpdir/sh.zip
        link="https://github.com/${is_sh_repo}/releases/download/${latest_ver}/code.zip"
        download_file
        unzip -qo $tmpfile -d $is_sh_dir
        chmod +x $is_sh_bin
        ;;
    dat)
        name="geoip.dat"
        tmpfile=$tmpdir/geoip.dat
        link="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        download_file
        name="geosite.dat"
        tmpfile=$tmpdir/geosite.dat
        link="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        download_file
        cp -f $tmpdir/*.dat $is_core_dir/bin/
        ;;
    caddy)
        name="Caddy"
        tmpfile=$tmpdir/caddy.tar.gz
        # https://github.com/caddyserver/caddy/releases/download/v2.11.2/caddy_2.11.2_linux_amd64.tar.gz
        link="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver:1}_linux_${caddy_arch}.tar.gz"
        download_file
        [[ ! $(type -P tar) ]] && {
            rm -rf $tmpdir
            err "请安装 tar"
        }
        tar zxf $tmpfile -C $tmpdir
        cp -f $tmpdir/caddy $is_caddy_bin
        chmod +x $is_caddy_bin
        ;;
    esac
    rm -rf $tmpdir
    unset latest_ver
}
download_file() {
    if ! _wget -t 5 -q -c $link -O $tmpfile; then
        rm -rf $tmpdir
        err "\n下载 ${name} 失败.\n"
    fi
}
