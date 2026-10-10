# Xray VLESS + REALITY 安装脚本(Hardened / 审计加固版)

[English](README.en.md) | 简体中文

**这是什么**:一个在 **Linux VPS / Docker 容器**上一键安装并管理 **Xray VLESS + REALITY** 代理服务的脚本。首次运行自动完成全部安装——下载 Xray 内核、生成 REALITY 密钥与客户端凭据、配置服务与开机自启、输出连接链接和二维码;之后再次运行进入管理菜单——添加/删除客户端、重启服务、彻底卸载。无需域名、无需证书,支持 **TCP + XTLS Vision** 与 **XHTTP** 两种传输,默认拦截客户端对服务器私网/云元数据地址的访问,交互界面支持**中英双语**。

本项目基于 [ndatg/xray-vless-reality-installer](https://github.com/ndatg/xray-vless-reality-installer) 完成了**全量安全审计与加固**,修复 20+ 项安全与健壮性问题:systemd 服务沙箱隔离、交互输入校验(防配置注入)、凭据随机性(全部改用 /dev/urandom)、BBR 失败不再中断安装、Alpine/busybox 兼容、REALITY 公钥自动恢复等,逐项说明见 **[AUDIT_REPORT.md](AUDIT_REPORT.md)**。上游采用 MIT 许可,本项目同样以 MIT 发布。

## 快速开始

一条命令即可在任意 Linux VPS 上安装并管理 VLESS + REALITY 服务端,传输层可选 TCP + XTLS Vision 或 XHTTP。无需域名、无需证书,开箱即用,两分钟内完成部署。针对没有 systemd 的 Docker 容器另有专用脚本。

VPS(root 执行):

```bash
wget https://raw.githubusercontent.com/lengxiv/xray-reality-hardened/main/xray-install.sh && sudo bash xray-install.sh
```

之后管理客户端(添加/删除等),再次运行 `sudo bash xray-install.sh` 即可。

## 交互语言 / Interface Language

两个脚本的所有交互文案均为**双语(English / 中文)**:

- 启动时会出现一次性语言选择(默认值按系统 locale 自动预选,直接回车即可);
- 用环境变量跳过提问:`XRAY_INSTALL_LANG=zh sudo -E bash xray-install.sh`(或 `en`);
- 管道/自动化运行(非交互 stdin)不会提问,直接使用 locale 默认语言;
- 菜单、提示、警告、安装摘要全部跟随所选语言,仅机器输出(URI、二维码、日志路径)保持原样。

### 在 Docker 容器中运行(无 systemd)

在 Docker 容器内(Debian/Ubuntu、Fedora、Alpine、Arch 镜像)使用 `xray-install-docker.sh`。以 root 运行,且需要 bash:

```bash
wget https://raw.githubusercontent.com/lengxiv/xray-reality-hardened/main/xray-install-docker.sh && bash xray-install-docker.sh
```

与宿主机版脚本的差异:
- Xray 以后台进程运行,日志在 `/var/log/xray.log`
- 日志不会自动轮转,长期运行的容器请定期清理 `/var/log/xray.log`
- 没有 systemd 服务单元、专用用户和 BBR
- 需要发布容器的 443 端口(如 `docker run -p 443:443 ...`)
- 无 systemd 环境的自启方式自动检测:
  - **cron**(容器内有 cron 守护进程时):每分钟检查一次,容器重启后*和* Xray 崩溃后都会自动恢复
  - 否则使用 **OpenRC**(`/etc/local.d`)或 **`/etc/rc.local`**:容器启动时拉起 Xray
  - 两者都不可用时,把服务商的启动命令设为 `/usr/local/bin/xray-autostart`,或从菜单手动启动(**Start / restart Xray**)

## 脚本功能

**首次运行** —— 交互式安装:
- 安装 Xray-core(最新版本,自动识别 CPU 架构)
- 自动探测服务器公网 IP,可直接使用,也可改填域名
- 生成 REALITY 密钥、UUID、Short ID
- 选择传输层:**TCP + XTLS Vision**(默认,所有客户端都支持)或 **XHTTP**(见下文)
- 对 SNI 站点做 REALITY 目标检查(TLS 1.3、HTTP/2、不跳转到其他域名),不达标会先警告再继续
- 选择 DNS(Google、Cloudflare、Quad9、AdGuard、OpenDNS)
- 配置加固的 systemd 服务,监听 443 端口,开机自启(专用用户、最小 capabilities、文件系统/系统调用沙箱)
- 若 UFW 或 firewalld 处于启用状态,自动放行 443 端口
- 配置写入前先校验,并确认 Xray 真正启动成功(失败时展示日志)
- 默认拦截客户端对服务器本机/私网地址的访问(见下文)
- 开启 TCP BBR 提升速度(重启后持久生效)
- 输出连接链接和二维码

**之后每次运行** —— 显示服务状态并进入管理菜单:

```
Xray VLESS+REALITY is already installed.

   Service  : active (since Thu 2026-09-25 21:00:00 MSK)
   Autostart: enabled
   Version  : 26.3.27
   Address  : 203.0.113.10
   SNI      : www.cloudflare.com
   Transport: TCP + XTLS Vision
   Clients  : 3
   Log      : journalctl -u xray

Select an option:
   1) Add a new client
   2) Remove an existing client
   3) Start / restart Xray
   4) Remove Xray
   5) Exit
```

(菜单支持中英双语,此处以英文输出为例。)

若开机自启曾被关闭,脚本会重新启用。配置变更(添加/删除客户端)会先校验、再替换正在运行的配置。如果现有配置由缺少私网拦截规则的旧版本生成,脚本会主动提议补上。

**卸载(Remove Xray)** 会删除 Xray 二进制、配置、服务和 BBR 设置。

## 环境要求

- Linux VPS(Debian、Ubuntu、CentOS、Fedora、Arch)
- root 权限
- 443 端口可用
- 用于客户端链接的服务器地址:域名或 IPv4(不支持 IPv6 字面量)

所有依赖均由脚本自动安装。

## 工作原理

REALITY 是 Xray 团队推出的新一代安全层,能让代理流量与访问真实网站(SNI 站点,如 `www.cloudflare.com`)的普通 HTTPS 连接无法区分。与传统 TLS 代理不同,REALITY 不需要证书、也不需要域名——只要一台有公网 IP 的 VPS。在 REALITY 之上,流量以 TCP + XTLS Vision 或 XHTTP 两种方式承载(见下文)。

### 选择 SNI 站点

SNI 站点应为境外站点,满足支持 TLS 1.3 与 HTTP/2(XHTTP 必需)、不跳转到其他域名——安装时脚本会自动检查。相比 Google、Microsoft、Apple 这类热门域名,优先选择与 VPS 处于同一网络的站点:一台 VPS 的 IP 自称是它们,很容易被识破。个别站点能通过检查但实际用于 REALITY 时仍会失败(如证书链很长的 `www.microsoft.com`),安装后请实测一次连接。

## 传输层:TCP + Vision 或 XHTTP

| | TCP + XTLS Vision | XHTTP |
|---|---|---|
| 客户端支持 | 所有应用 | 内核为较新 Xray-core 的应用,见[客户端应用](#客户端应用) |
| 流量形态 | 一条长 TLS 连接 | 形似普通 HTTP 请求(更难按连接模式被指纹识别) |
| flow | `xtls-rprx-vision` | 无(Vision 仅适用于 TCP) |

XHTTP 遵循 [Project X 官方示例](https://github.com/XTLS/Xray-examples/tree/main/VLESS-XHTTP-Reality):只设置随机 `path`,`mode` 为 `auto`(客户端在 REALITY 下选择 `stream-one`),其余均为 Xray 默认值。要求 Xray-core v25.3.6 及以上。使用 XHTTP 时,客户端应用中**不要**开启 Mux(mux.cool)。

传输层在安装时选定;如需切换,重新安装即可(客户端链接会更新)。

## 私网地址拦截

客户端只能通过本服务器访问互联网,发往服务器自身及内网地址的连接一律丢弃:

- `127.0.0.0/8`、`::1` —— 服务器本机上的服务(数据库、管理面板、监听 localhost 的 API)
- `10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、`100.64.0.0/10`、`fc00::/7` —— 服务商内网/局域网、Docker 宿主机
- `169.254.0.0/16`、`fe80::/10` —— 链路本地地址,包括云元数据服务 `169.254.169.254`
- `224.0.0.0/4`、`240.0.0.0/4`、`ff00::/8` —— 组播与保留段

解析到上述地址的主机名同样被覆盖(`localhost`、`/etc/hosts` 条目、指向 `127.0.0.1` 的公网域名)。Xray 自身的 DNS 查询走直连,本机系统解析器不受影响。如需放行,删除 `/etc/xray/config.json` 中 `routing.rules` 里 `"outboundTag": "block"` 的那条规则并重启 Xray。安装时的一次性询问若被拒绝会被记住(`/etc/xray` 下的标记文件),不会每次运行都重复询问。

## 客户端应用

导入生成的链接或扫描二维码即可。下表所有应用都支持 **TCP + XTLS Vision**。**XHTTP** 是 Xray-core 的特性:基于较新 Xray-core(v25.3.6+)构建的应用支持,基于 sing-box 的应用通常不支持。

| 平台 | 应用 | XHTTP |
|------|-----|-------|
| iOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118), [V2BOX](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) | 视应用版本而定 |
| macOS | [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118), [V2BOX](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) | 视应用版本而定 |
| Android | [v2rayNG](https://github.com/2dust/v2rayNG) | 支持(Xray-core) |
| Android | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) | 不支持(sing-box 内核) |
| Windows | [v2rayN](https://github.com/2dust/v2rayN) | 支持(Xray-core) |
| Linux | [v2rayA](https://github.com/v2rayA/v2rayA) | 支持(需 Xray-core) |
| Linux | [Nekoray](https://github.com/Mahdi-zarei/nekoray), [Hiddify](https://github.com/hiddify/hiddify-app) | 通常不支持(sing-box 内核) |

使用 XHTTP 时,请保持应用中的 **Mux** 处于关闭状态。

## 文件位置

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/xray` | Xray-core 二进制 |
| `/etc/xray/config.json` | 服务端配置 |
| `/etc/xray/public.key` | REALITY 公钥 |
| `/etc/xray/server.addr` | 客户端链接使用的服务器地址(IP 或域名) |
| `/etc/xray/vless-*.png` | 二维码图片 |
| `/etc/systemd/system/xray.service` | systemd 服务单元 |
| `/etc/sysctl.d/99-xray-bbr.conf` | TCP BBR 设置 |

## 许可证

MIT
