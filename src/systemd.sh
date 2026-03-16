install_service() {
    case $1 in
    xray | v2ray)
        is_doc_site=https://xtls.github.io/
        [[ $1 == 'v2ray' ]] && is_doc_site=https://www.v2fly.org/
        cat >/lib/systemd/system/$is_core.service <<<"
[Unit]
Description=$is_core_name Service
Documentation=$is_doc_site
Wants=network-online.target
After=network-online.target nss-lookup.target
StartLimitIntervalSec=0

[Service]
#User=nobody
User=root
NoNewPrivileges=true
ExecStart=$is_core_bin run -config $is_config_json -confdir $is_conf_dir
Restart=always
RestartSec=5s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target"
        ;;
    caddy)
        cat >/lib/systemd/system/caddy.service <<<"
#https://github.com/caddyserver/dist/blob/master/init/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=notify
User=root
Group=root
ExecStart=$is_caddy_bin run --environ --config $is_caddyfile --adapter caddyfile
ExecReload=$is_caddy_bin reload --config $is_caddyfile --adapter caddyfile
Restart=always
RestartSec=5s
TimeoutStopSec=5s
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
#AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target"
        ;;
    esac

    # enable, reload
    systemctl daemon-reload
    systemctl enable $1
}

install_logrotate() {
    cat >/etc/logrotate.d/$is_core <<EOF
$is_log_dir/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 root root
}
EOF
}
