# Xray 一键安装 & 管理脚本

## 功能特点

- 一键安装，零配置上手
- 自动化 TLS（Caddy 自动申请证书）
- 多配置同时运行，支持所有常用协议
- **自动生成订阅链接**（Sing-box / Mihomo / 通用 Base64）
- **添加/删除节点后订阅自动更新**
- **自动管理系统防火墙端口**（ufw / firewalld）
- 支持 API 操作，无需重启即可增删节点
- 查看配置时自动显示节点二维码
- 一键启用 BBR 加速

## 支持协议

| 协议 | 传输 | Cloudflare | 说明 |
|------|------|:----------:|------|
| VMess-TCP | TCP | | 经典协议，无 TLS，不可过 Cloudflare |
| VMess-mKCP | mKCP | | 基于 UDP，Cloudflare 不支持 UDP 中转 |
| VMess-WS-TLS | WebSocket | ✓ | 兼容性好，Cloudflare 免费套餐可用 |
| VMess-gRPC-TLS | gRPC | ✓ | Cloudflare 需开启 gRPC 支持（Pro 套餐） |
| VLESS-WS-TLS | WebSocket | ✓ | 兼容性最好，Cloudflare 免费套餐可用（443/80/8443 等端口） |
| VLESS-gRPC-TLS | gRPC | ✓ | 低延迟，Cloudflare 需开启 gRPC 支持（Pro 套餐） |
| VLESS-XHTTP-TLS | XHTTP | ✓ | 新型传输，行为类似 HTTPS 下载，Cloudflare 可代理 |
| VLESS-REALITY | TCP | | 推荐使用，抗检测能力强，直连无需域名 |
| Trojan-WS-TLS | WebSocket | ✓ | 流量伪装为 HTTPS，Cloudflare 免费套餐可用 |
| Trojan-gRPC-TLS | gRPC | ✓ | Cloudflare 需开启 gRPC 支持（Pro 套餐） |
| Shadowsocks | TCP | | 轻量加密代理，支持 SS2022，直连使用 |
| VMess-TCP-dynamic-port | TCP | | 动态端口，防端口封锁，不可过 Cloudflare |
| VMess-mKCP-dynamic-port | mKCP | | 动态端口 + UDP，Cloudflare 不支持 |
| Socks5 | TCP | | 本地 SOCKS5 代理，仅供本机使用 |

> **Cloudflare 使用说明**：标记 ✓ 的协议需将域名托管至 Cloudflare，服务器监听 443 端口，Xray 配置域名后 Cloudflare 自动代理流量（小云朵开启）。WebSocket 协议免费套餐即可使用；gRPC 协议需 Pro 套餐并在 Cloudflare 控制台开启「gRPC」选项。

## 系统要求

- 操作系统：Ubuntu / Debian / CentOS
- 架构：64 位（x86_64 或 ARM64）
- 权限：root 用户
- 依赖：systemd

## 安装

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wade0317/Xray/main/install.sh)
```

如果服务器无法访问 GitHub，可下载源码后本地安装：

```bash
# 1. 在本机下载源码包
wget https://github.com/wade0317/Xray/archive/refs/heads/main.zip

# 2. 上传到服务器并解压
scp main.zip root@your-server:/root/
ssh root@your-server "unzip main.zip && cd Xray-main && bash install.sh"
```

安装完成后默认添加一个 **VLESS-REALITY** 配置，并自动：
- 开放对应防火墙端口（如 ufw/firewalld 已启用）
- 生成订阅文件并输出订阅链接

## 使用

安装完成后使用 `xray` 命令管理：

```bash
xray [command] [args]
```

### 常用操作

```bash
# 添加节点（交互式选择协议）
xray add

# 快速添加指定协议
xray add reality          # VLESS-REALITY
xray add reality auto     # 自动参数
xray add ws               # VMess-WS-TLS
xray add vws              # VLESS-WS-TLS
xray add ss               # Shadowsocks

# 查看节点信息 / 二维码 / URL
xray info [name]
xray qr [name]
xray url [name]

# 删除节点
xray del [name]

# 查看订阅链接
xray sub
```

### 订阅链接

每次添加或删除节点后，脚本自动重新生成以下三种订阅文件：

| 类型 | 适用客户端 |
|------|----------|
| Clash (Mihomo) 订阅地址 - 推荐 | Clash Verge Rev、Mihomo |
| Sing-box 订阅地址 | Sing-box、Sing-box VT |
| V2ray/NekoBox 通用订阅地址 (Base64) | v2rayN、NekoBox 等 |

**IP 直连订阅（默认，无需域名）：**

```
http://{ip}:2096/{token}/clash.yaml
http://{ip}:2096/{token}/singbox.json
http://{ip}:2096/{token}/base64.txt
```

**HTTPS 域名订阅（配置域名后自动启用）：**

```
https://{domain}/sub/{token}/clash.yaml
https://{domain}/sub/{token}/singbox.json
https://{domain}/sub/{token}/base64.txt
```

使用 `xray sub` 随时查看当前订阅链接。

> 订阅端口默认为 **2096**，Token 在安装时随机生成，存储于 `/etc/xray/subscribe/token`。
> 配置域名后会同时提供 HTTPS 域名链接和 IP 直连备用链接。

### 推荐客户端

| 客户端 | 平台 | 订阅格式 | 下载 |
|--------|------|----------|------|
| [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) | Windows / macOS / Linux | Mihomo (clash.yaml) | [GitHub Releases](https://github.com/clash-verge-rev/clash-verge-rev/releases) |
| [Sing-box](https://github.com/SagerNet/sing-box) | iOS / Android / 桌面 | Sing-box (singbox.json) | [GitHub Releases](https://github.com/SagerNet/sing-box/releases) |
| Sing-box VT | iOS | Sing-box (singbox.json) | [App Store](https://apps.apple.com/us/app/sing-box-vt/id6673731168) |

### 订阅模板

订阅配置基于模板生成，模板位于安装目录下：

```
/etc/xray/sh/template/
├── sing-box-vpn.json   # Sing-box 客户端模板
└── clash-vpn.yaml      # Mihomo/Clash 客户端模板
```

修改模板后，执行任意 `xray add` 或 `xray del` 操作，新的订阅文件将自动使用更新后的模板。

### 防火墙管理

脚本自动检测并管理系统防火墙（**仅在防火墙已启用时生效**，不会主动启用未启用的防火墙）：

| 操作 | 防火墙行为 |
|------|----------|
| `xray add` | 自动开放对应端口（TLS 协议开放 443，直连协议开放监听端口） |
| `xray del` | 检查端口是否仍被使用，无其他配置使用时自动关闭 |
| 安装时 | 自动开放订阅端口 2096 |

支持 **ufw**（Ubuntu/Debian）和 **firewalld**（CentOS）。

> 云服务器（阿里云、腾讯云、AWS 等）的**安全组规则**需在云控制台手动添加，脚本无法自动配置。

### 完整命令参考

```
基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 xray x25519
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   sub                                             显示订阅链接
   log                                             查看日志
   logerr                                          查看错误日志

更改:
   dp, dynamicport [name] [start | auto] [end]     更改动态端口
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | auto] [Public key]    更改密钥
   type [name] [type | auto]                       更改伪装类型
   method [name] [method | auto]                   更改加密方式
   sni [name] [ip | domain]                        更改 serverName
   seed [name] [seed | auto]                       更改 mKCP seed
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json

管理:
   un, uninstall                                   卸载
   u, update [core | sh | dat | caddy] [ver]       更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   client [name]                                   显示用于客户端 JSON, 仅供参考
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件
   genc [name]                                     显示用于客户端部分 JSON, 仅供参考
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS
   xapi [...]                                      同等于 xray api, 使用当前运行的 Xray 服务

其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 Xray 命令
   api, x25519, tls, run, uuid [...]               兼容 Xray 命令
   h, help                                         显示帮助
```

## 目录结构

安装后的文件位于：

```
/etc/xray/
├── bin/                # Xray-Core 二进制及规则库
├── conf/               # 节点配置文件（每个节点一个 JSON）
├── config.json         # 主配置文件
├── subscribe/          # 订阅文件目录
│   └── {token}/
│       ├── base64.txt
│       ├── singbox.json
│       └── clash.yaml
└── sh/                 # 管理脚本
    └── template/       # 订阅配置模板
```

## 问题反馈

[提交 Issue](https://github.com/wade0317/Xray/issues)
