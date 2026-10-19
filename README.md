# 🚀 Sing-box Docker Server Manager

> 基于 Docker 与 Trojan over TLS 协议的极简、安全、高性能代理服务一键部署方案。支持 Let's Encrypt 自动化正规证书与主动探测伪装回落。

<p align="left">
  <img src="https://img.shields.io/badge/Core-Sing--box-blue?style=flat-square&logo=go" alt="Sing-box">
  <img src="https://img.shields.io/badge/Container-Docker-blue?style=flat-square&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Protocol-Trojan--TLS-orange?style=flat-square" alt="Protocol">
  <img src="https://img.shields.io/badge/Cert-Let's_Encrypt_ACME-brightgreen?style=flat-square" alt="Cert">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

---

## 📖 项目简介

本项目旨在通过高度自动化的脚本，在您的 Linux 服务器上一键拉取并部署官方最新的 **Sing-box** 代理服务端。服务独占 **`443`** 端口与 **`80`** 端口（用于证书签发），采用 **Trojan** 协议并集成 **Let's Encrypt 原生自动化 ACME** 证书签发。

无需在宿主机额外安装复杂的 Certbot 或申请第三方 Cloudflare API Token，即可全自动获得权威 CA 信任的真实 TLS 证书，实现客户端 `allowInsecure: false` 的高标准安全加密传输。

### 🛡️ 工作原理与防探测架构

```text
外部请求 (HTTPS 443)
       │
       ▼
[sing-box 容器] (监听 443，Let's Encrypt 权威 TLS 证书)
       │
       ├─ 是 Trojan 握手 ──► 校验密码通过 ──► 极速代理上网 (全平台客户端)
       │
       └─ 是普通 HTTP 请求 (拉取订阅 / GFW 探测 / 浏览器直接访问)
              │ (触发 fallback 回落)
              ▼ (Docker 内部网络通信，公网无端口暴露)
       [sub-server 容器] (Nginx 内部服务)
              │
              ├─ 访问 /subs/<hash>.json ──► 安全返回 Sing-box 客户端订阅配置
              └─ 访问其他任意路径/探测 ──► 返回标准 Nginx 欢迎页，完美伪装站
```

1. **零端口暴露的 HTTPS 订阅**：内置的 Nginx 订阅容器完全运行于 Docker 私有内部网络，公网不开放任何明文端口（如 8080）。所有订阅分发均经过 `sing-box` 443 端口的 TLS 强加密与反向回落，杜绝凭证嗅探与明文泄露。
2. **反主动探测 (Active Probing Defense)**：墙或恶意扫描器对 443 端口发起普通 HTTPS 探测时，服务端直接回落并呈现合法的 Nginx 静态站点，有效抵御主动探测特征识别。

---

## ✨ 核心特性

*   🔒 **Let's Encrypt 原生正规证书**：检测到域名时全自动配置 Sing-box 内置 ACME 申请权威证书并全自动续期；纯 IP 部署时自动生成包含 SAN 的 10 年期自签名证书兜底。
*   🛡️ **全平台真实安全（无 Insecure 警告）**：使用域名部署时，客户端彻底关闭 `insecure / allowInsecure`，杜绝中间人攻击（MITM）。
*   🌐 **全平台多客户端无缝兼容**：针对 Sing-box 最新规范严格适配，解决移动端嗅探规则、macOS 本地 DNS `detour` 报错及 HTTP/2 协议帧冲突问题，完美兼容 Android、iOS、macOS、Windows 及 Linux。
*   📦 **纯 Docker Compose 编排**：宿主机零环境污染，无外部脚本或额外 CLI 依赖，一键拉取镜像、一键热启。
*   👥 **多用户管理文件化**：在 `config/users.txt` 中按行增删用户名，即可全自动维护多用户节点。
*   🔄 **非破坏性增量更新**：重运行部署脚本时，**自动保留已有老用户的连接密码与订阅 Hash**，老用户无需重复导入。
*   🔗 **双模订阅一键生成**：
    - **官方 JSON 订阅**：专为 Sing-box 官方客户端定制的 `https://<域名>/subs/<token>.json` 地址，支持定时自动更新。
    - **标准 Trojan 链接**：兼容 Shadowrocket、Surfboard、Karing、Clash 等各大第三方主流客户端。

---

## 📂 目录结构

```text
.
├── docker-compose.yml       # Docker 服务容器编排文件 (sing-box + 内部 sub-server)
├── singbox.sh               # 交互式命令行控制面板脚本
├── README.md                # 项目文档
├── www/                     # [伪装网站] SkyTrading 量化与金融研究主页
│   └── index.html
└── config/                  # 配置数据持久化目录
    ├── users.txt            # [用户维护] 每一行配置一个用户名
    ├── config.json          # [自动生成] 服务端 sing-box 主配置文件
    ├── client_links.txt     # [自动生成] 备份的客户端直连节点与订阅链接
    ├── <username>_client.json # [自动生成] 专为官方 Sing-box 客户端定制的 JSON 配置
    ├── acme/                # [自动生成] Let's Encrypt 证书与账户缓存目录
    └── subs/                # [自动生成] 订阅分发目录，映射至内部 Nginx
```

---

## ⚡ 快速开始

### 1. 前置准备

1. **域名解析**：准备一个域名（如 `us.skytrading.site`），将其 **A 记录** 解析至您的 VPS 服务器公网 IP。
   - 若使用 Cloudflare，请将小云朵保持为**灰云（DNS only / 仅限 DNS）**，不要开启代理（Proxy）。
2. **放行端口**：确保服务器防火墙安全组已放行 **`80/tcp`**、**`443/tcp`** 与 **`443/udp`** 端口，且未被宿主机的其他 Web 服务占用。

### 2. 一键启动部署

在服务器终端中以 **root** 权限调起交互式管理面板：

```bash
sudo bash singbox.sh
```

首次运行选择 `1. 安装/更新服务`，根据提示输入您的域名（如 `us.skytrading.site`）即可全自动完成证书申请、服务拉起与配置生成。

---

## 🛠️ 控制面板功能介绍

通过运行 `sudo bash singbox.sh`，可随时呼出管理菜单：

1. **Install & Deploy Service**：首次部署或变更域名/IP。全自动完成环境检测、ACME 证书配置并拉起容器。
2. **Start Service**：一键启动 Sing-box 与订阅容器。
3. **Stop Service**：一键停止容器运行。
4. **Restart Service**：重启容器使新改动即刻生效。
5. **Uninstall Service**：彻底卸载清理（包含容器、镜像与配置目录）。
6. **Update Sing-box Version**：一键拉取官方最新镜像并无缝平滑升级。
7. **Show Trojan Links & QR Codes**：列出所有用户的标准 Trojan 链接、HTTPS 订阅地址及控制台二维码。
8. **Add User**：添加新用户（自动增量重载，**完全保留老用户密码与订阅地址**）。
9. **Delete User**：安全移除指定用户并重载服务。
10. **View Real-time Logs**：实时查看代理日志（自动携带 `--tail=100`，支持安全退出）。

---

## 📱 客户端导入指引

### 方式一：官方 Sing-box 客户端（推荐首选，支持自动更新）

适用平台：**Android**、**iOS**、**macOS**、**Windows**、**Linux**

1. 下载安装官方 [Sing-box 客户端](https://github.com/SagerNet/sing-box/releases)（iOS 用户可在美区 App Store 搜索 Sing-box）。
2. 打开客户端，进入 **Profiles**（配置）页面，点击 **+ (添加)**。
3. 填写配置信息：
   - **Name**：任意填写（如 `MyProxy`）
   - **Type**：选择 **Remote**
   - **URL**：粘贴脚本输出的专属 HTTPS 订阅链接：
     ```text
     https://<您的域名>/subs/<用户Hash>.json
     ```
   - **Auto Update**：建议开启，时间间隔设为 `60` 分钟。
4. 点击 **Create / Save** 保存，返回主页点击启用即可。

---

### 方式二：标准 Trojan 节点导入（第三方客户端）

复制脚本输出的 `trojan://` 链接，直接粘贴导入至以下客户端：

| 平台 | 推荐客户端 | 导入格式 | 特性说明 |
| :--- | :--- | :--- | :--- |
| **iOS** | **[Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)** | `trojan://` 链接 | 原生极速，支持规则分流与测速 |
| | **[Karing](https://apps.apple.com/us/app/karing/id6472431552)** | 订阅 URL / `trojan://` | 界面现代美观，兼容全平台 |
| **macOS** | **[Sing-box (官方)](https://github.com/SagerNet/sing-box/releases)** | 远程订阅 URL | 官方内核驱动，系统占用极低 |
| | **[Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)** | `trojan://` 链接 | 兼容 Apple Silicon Mac |
| **Android** | **[Sing-box (官方)](https://github.com/SagerNet/sing-box/releases)** | 远程订阅 URL | 原生 Tun 虚拟网卡，防泄露，**强烈推荐** |
| | **[Surfboard](https://github.com/getsurfboard/surfboard/releases)** | `trojan://` 链接 | 界面美观优雅，支持各类节点 |
| **Windows** | **[Sing-box (官方)](https://github.com/SagerNet/sing-box/releases)** | 远程订阅 URL | 轻量快捷 |
| | **[Karing](https://karing.app)** | 订阅 URL / `trojan://` | GUI 完善，开箱即用 |
| **OpenWrt** | **[PassWall](https://github.com/Openwrt-Passwall/openwrt-passwall)** / **[HomeProxy](https://github.com/immortalwrt/homeproxy)** | `trojan://` 链接 | 路由器透明代理首选 |

> [!NOTE]
> 使用域名部署且申请了权威证书时，所有客户端的 **`Allow Insecure / 允许不安全证书` 均可保持关闭（推荐）**，连接受到受信任 CA 的全程严密防护。