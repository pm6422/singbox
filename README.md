# 🚀 Sing-box Docker Deployment Kit

> 基于 Docker 与 VLESS-XTLS-Reality 协议的极简、安全、高性能代理服务一键部署方案。

<p align="left">
  <img src="https://img.shields.io/badge/Core-Sing--box-blue?style=flat-square&logo=go" alt="Sing-box">
  <img src="https://img.shields.io/badge/Container-Docker-blue?style=flat-square&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Protocol-VLESS--XTLS--Reality-orange?style=flat-square" alt="Protocol">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

---

## 📖 项目简介

本项目旨在通过高度自动化的脚本，在您的 Linux 服务器上一键拉取并部署官方最新的 **Sing-box** 代理服务端。服务独占 **`443`** 端口，借助 **Reality** 协议的证书借用特性，无需自备域名和证书，即可实现极高抗封锁性的加密数据传输。

### 🛡️ 工作原理与伪装架构

当流量到达您的服务器 `443` 端口时，Sing-box 会对其执行 TLS 验证。如果是来自您客户端的合法认证流量，将建立安全代理通道；如果是第三方主动探测或普通用户流量，则会无感重定向（回落）至目标网站。

```mermaid
graph TD
    Client["📱 客户端 (Shadowrocket / Stash / v2rayN 等)"] -->| "发送 TLS 握手 (SNI: www.microsoft.com)" | Server["🐳 Sing-box 容器 (监听宿主机 443 端口)"]
    Server -->| "验证 Reality 证书签名 & Short ID" | Auth{"🔍 校验通过?"}
    Auth -->| "是 (合法代理请求)" | Proxy["🚀 建立加密隧道，转发至目标网站"]
    Auth -->| "否 (主动探测或普通访问)" | Fallback["🔒 安全回落 (Forward 流量至 www.microsoft.com)"]
    
    style Auth fill:#f9f,stroke:#333,stroke-width:2px
    style Proxy fill:#d4edda,stroke:#28a745,stroke-width:2px
    style Fallback fill:#fff3cd,stroke:#ffc107,stroke-width:2px
```

---

## ✨ 核心特性

*   🔒 **无感完美伪装**：采用先进的 Reality 偷渡技术，偷用大厂（默认 `www.microsoft.com`）合法的 TLSv1.3 证书进行混淆，完美逃避主动探测。
*   👥 **多用户管理文件化**：在 `config/users.txt` 中通过简单的按行增删用户名，即可全自动维护多用户节点。
*   🔄 **非破坏性增量更新**：重运行部署脚本时，**自动保留已有老用户的 UUID 凭证与服务器私钥**。老用户无需重新导入配置，仅对新加入用户做增量派发，对移出的用户做即时停用。
*   🔗 **一键导出直连**：部署完成或更新配置后，终端将以高亮色彩批量生成所有用户的专属 `vless://` 连接，即刻扫码或复制导入客户端。

---

## 📂 目录结构

项目目录已实现最精简、扁平的设计：

```text
.
├── docker-compose.yml       # Docker 服务容器编排文件
├── deploy.sh                # 自动化部署与增量用户配置脚本
├── README.md                # 项目文档
└── config/                  # 配置数据持久化目录
    ├── users.txt            # [用户维护] 每一行配置一个用户名
    ├── config.json          # [自动生成] 服务端 sing-box 主配置文件
    └── client_links.txt     # [自动生成] 备份的客户端直连订阅链接
```

---

## ⚡ 快速部署

> [!IMPORTANT]
> 执行部署前，请确保您服务器的 **`443/tcp`** 和 **`443/udp`** 端口未被其他服务（如 Nginx, Apache 或 Caddy）占用，并且防火墙已放行上述端口。

### 1. 配置用户列表
在项目根目录下创建（或修改自动生成的） `config/users.txt`：
```text
pm6422
chenxin
# 您可以在下方继续追加新用户名，每行一个
new_user_1
```
*注：支持添加以 `#` 开头的注释行以及空行，脚本在运行时会自动跳过。*

### 2. 执行一键部署
无需手动授予可执行权限，直接通过 Bash 解释器运行脚本：

```bash
sudo bash deploy.sh
```

### 3. 部署后操作
脚本会自动执行以下所有流程，并在成功后在控制台打印生成的链接：
1. 校验并自动安装 Docker 环境。
2. 提示您输入绑定的域名（如果已为服务器 IP 配置了 DNS A 记录，输入域名即可在输出链接中自动替换 IP，无需手动修改；无域名直接回车即可）。
3. 自动生成 Reality 证书密钥，或安全重用历史凭证。
4. 增量派发 UUID 并写入 `config/config.json`。
5. 启动或平滑重启 Sing-box 服务并输出客户端订阅链接。

---

## 📱 客户端支持矩阵

复制部署输出的 `vless://` 链接并直接导入至以下推荐的主流客户端：

| 平台 | 推荐客户端 | 协议支持说明 |
| :--- | :--- | :--- |
| **iOS / macOS** | **Shadowrocket (小火箭)** | 原生完美支持，推荐首选 |
| | **Sing-box (官方)** | 官方客户端，原生支持 |
| | **Stash** | 采用 Mihomo 核心，完美支持 |
| **Android** | **v2rayNG** | 主流客户端，完美支持 Reality (Vision) |
| | **Nekobox** | 功能强大，支持一键测速与节点导入 |
| **Windows** | **Clash Verge Rev** | 推荐使用，基于新版 Mihomo 内核 |
| | **v2rayN** | 切换至 Xray/Sing-box 内核后可正常连通 |
| | **Nekobox (NekoRay)** | 客户端原生支持，延迟低 |

---

## 🛠️ 日常运维指南

所有的服务运维都可以通过标准的 Docker Compose 命令行完成。在项目根目录下执行：

| 操作 | 对应命令 |
| :--- | :--- |
| **启动服务** | `docker compose up -d` |
| **停止服务** | `docker compose down` |
| **重启 Sing-box** | `docker compose restart sing-box` |
| **实时查看日志** | `docker compose logs -f` |
| **拉取最新镜像并升级** | `docker compose pull && docker compose up -d` |

---

## 📝 配置文件说明
- **配置用户列表**：[config/users.txt](file:///Users/louislau/Workspace/singbox/config/users.txt) （日常只需修改此文件来增删用户）。
- **服务端运行配置**：[config/config.json](file:///Users/louislau/Workspace/singbox/config/config.json) （自动维护，切勿手动乱改，防格式损毁）。
- **已生成链接备份**：[config/client_links.txt](file:///Users/louislau/Workspace/singbox/config/client_links.txt) （包含用户专属连接，可随时打开复制）。