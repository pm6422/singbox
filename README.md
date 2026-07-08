# Sing-box Server 一键部署套件

基于 Docker 快速搭建一个极简、高性能的 Sing-box 代理服务器，采用主流的 **VLESS-XTLS-Reality** 协议。

## 特性

- 🔒 **高性能伪装**：采用 Reality 技术，无需自备域名和申请证书，直接伪装至公网大厂网站（默认伪装为 `www.microsoft.com`）。
- 👥 **用户文件化配置**：通过 `config/users.txt` 统一管理用户名，每行一个。
- 🔄 **智能增量更新**：新增或修改用户后再次运行部署脚本时，**原有的老用户凭证（UUID）和 Reality 密钥会被自动保留**，仅对新加入的用户执行新增。删除某行用户名即代表在服务器上将其安全停用。
- 🐳 **一键部署，零手工配置**：一键运行脚本，自动拉取、生成密钥对并写入配置文件，极其省心。
- 🔗 **扫码/复制即用**：部署成功后，终端将直接批量打印出所有用户的客户端直连链接，可方便快捷地导入客户端。

---

## 快速开始

### 1. 确认文件准备
确保您的目录中拥有以下三个核心文件：
- `docker-compose.yml` - Docker 编排配置
- `deploy.sh` - 自动化部署与增量配置生成脚本
- `config/users.txt` - 用户名列表文件（若不存在，脚本在首次运行时会默认自动创建并填入 `pm6422` 和 `chenxin`）

### 2. 管理用户列表（可选）
在运行部署前，您可以直接编辑 [config/users.txt](file:///Users/louislau/Workspace/singbox/config/users.txt) 增加或修改用户名，例如：
```text
zhansan
lisi
# 可以在这下面继续添加新用户，每一行一个名字：
new_user_1
new_user_2
```
*注：支持以 `#` 开头的注释行和空行，脚本会自动过滤它们。*

### 3. 执行部署脚本
在服务器终端中以 **root** 权限执行以下命令：

```bash
# 运行自动化部署
sudo bash deploy.sh
```

脚本将自动完成以下流程：
1. 检测并安装 Docker、Docker Compose。
2. 拉取 `sing-box` 官方 Docker 镜像。
3. 检查是否有历史配置，智能地复用已有的 Reality 证书秘钥。
4. 读取 `users.txt` 里的用户名，自动执行**增量更新**（老用户保留已有 UUID，新用户分配新 UUID，被移除的用户自动清除）。
5. 自动组装并将配置写入 `./config/sing-box/config.json`。
6. 使用 Docker Compose 在宿主机 **`443`** 端口启动/平滑重启服务使之生效。
7. **在控制台中高亮打印出所有活跃用户的专属客户端直连链接**。

---

## 客户端导入指南

您在部署完毕后将会获得如下格式的链接：
```text
vless://<UUID>@<SERVER_IP>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>#singbox-<USER_NAME>
```

直接复制相应用户的链接，导入以下主流客户端之一即可开始使用：
- **iOS / macOS**: Shadowrocket, Sing-box, Stash
- **Android**: v2rayNG, Sing-box, Nekobox
- **Windows**: v2rayN, Nekobox (NekoRay), Clash Verge Rev (Mihomo/Clash.Meta 核心)

---

## 服务管理命令

在项目目录下，您可以使用标准的 Docker Compose 命令管理容器：

- **查看日志（可用于排查连接问题）**：
  ```bash
  docker compose logs -f
  ```
- **重启服务**：
  ```bash
  docker compose restart
  ```
- **停止服务**：
  ```bash
  docker compose down
  ```
- **更新镜像与重启服务**：
  ```bash
  docker compose pull && docker compose up -d
  ```

---

## 配置文件说明
- **用户列表**：[config/users.txt](file:///Users/louislau/Workspace/singbox/config/users.txt) (用于直接增删用户名)。
- **服务器配置文件**：[config/config.json](file:///Users/louislau/Workspace/singbox/config/config.json) (部署脚本运行后生成)。
- **备份的客户端直连链接**：[config/client_links.txt](file:///Users/louislau/Workspace/singbox/config/client_links.txt) (部署脚本运行后自动生成与更新)。