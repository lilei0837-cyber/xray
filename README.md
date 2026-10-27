# Xray 一键部署：VLESS + REALITY / VMess + TCP

两个脚本均用于全新 Ubuntu 22.04 / 24.04（x86_64 或 aarch64），监听 TCP 443。**按需选一个部署**；不会把已有节点转换为另一个协议，也不能用这两个首次安装脚本在同一台服务器重复安装。

## VMess + TCP（vmess.sh）

通过 SSH 登录全新服务器，在 Linux 终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/lilei0837-cyber/xray/main/vmess.sh -o vmess.sh && sudo bash vmess.sh
```

- 核心：Xray；协议：VMess AEAD；传输：TCP；端口：443；客户端 alterId：0；加密：auto。
- 不启用 TLS、REALITY 或 HTTP 伪装，不需要域名和证书。使用 443 端口不代表启用了 HTTPS。
- 自动获取公网 IPv4、生成随机 UUID、写入配置、检查配置、启动服务并输出 `vmess://` 连接。
- 预装 curl，具备 sudo/root 权限，使用 systemd；云安全组应放行入站 TCP 443。
- 检查已有 Xray、V2Ray、x-ui、sing-box 服务/配置及端口占用；发现冲突时停止，不覆盖原节点。
- VMess 依赖准确时间。脚本检查系统 NTP 同步状态；未同步时尝试启用系统已有的 NTP 服务并最多等待约 30 秒，失败则停止。客户端也需时间准确。
- UFW 已启用时放行 TCP 443；不会修改云安全组或其他防火墙。
- 下载并运行 XTLS 官方安装器，使用当时提供的 Xray 版本；失败后可能保留部分安装，需先检查错误。

再次查看连接：

```bash
sudo cat /root/xray-vmess-link.txt
```

配置文件：`/usr/local/etc/xray/config.json`。连接含访问凭据，请勿公开。

### VMess 验证情况

本地执行 `python test_vmess.py`：10 项检查通过，覆盖 Bash/Python 语法、生成配置与链接一致性、随机 UUID、公网 IPv4 校验、已有配置/程序及端口占用保护、时间同步检查。保护逻辑使用隔离片段和模拟命令测试。

测试要求 Python 3 和 Bash；Linux 使用 PATH 中的 bash，Windows 默认使用 Git Bash，可通过 BASH_EXE 指定位置。

尚未在真实 Ubuntu / EC2 上执行完整安装，未验证真实 Xray 配置加载、systemd/UFW 操作或客户端端到端连接。安装过程会执行 Xray 自带配置检查及服务启动检查。

参考：[Xray VMess 文档](https://xtls.github.io/en/config/inbounds/vmess.html)、[v2rayN 分享链接格式](https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link)。

---

## VLESS + REALITY（install.sh）

面向全新 Ubuntu 22.04 / 24.04 服务器，支持 x86_64 和 aarch64。使用 VLESS + REALITY + XTLS Vision，TCP 端口固定为 **443**，默认 SNI / 目标为 `www.ibm.com`。

## 一条命令部署

通过 SSH 登录服务器，在服务器的 Linux 终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/lilei0837-cyber/xray/main/install.sh -o xray-install.sh && sudo bash xray-install.sh
```

需要预装 curl、可用的 sudo/root 权限、systemd、空闲的 TCP 443 端口和可被客户端访问的公网 IPv4。云服务器安全组应放行入站 TCP 443。本命令是 Bash/Linux 命令，不是 Windows PowerShell 部署命令。

脚本会下载并运行 XTLS 官方安装器，安装 Xray；自动生成 UUID、REALITY 密钥和 short ID；检查配置并启动服务；最后输出可以导入兼容客户端的 `vless://` 连接。部署过程需要访问 Ubuntu 软件源、GitHub 和默认 REALITY 目标。

## 连接与服务

再次查看连接：

```bash
sudo cat /root/xray-reality-link.txt
```

查看服务状态和日志：

```bash
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 50 --no-pager
```

服务端配置保存在 `/usr/local/etc/xray/config.json`。连接包含访问凭据，请勿公开分享；私钥只保留在服务器配置中。

## 行为与限制

- 仅用于首次安装；检测到已有 Xray、V2Ray、x-ui 或相关配置时会停止，避免覆盖。
- 安装前检查默认目标的 TLS 1.3 和 HTTP/2 支持；检查失败会停止。
- UFW 已启用时添加 TCP 443 放行规则；不会自动修改云安全组或其他防火墙。
- 不需要为服务器申请域名或证书。默认目标的可用性依赖服务器所在网络。
- 安装失败可能保留已安装的软件和部分文件，请先检查错误，不要直接删除已有配置。
- 使用官方安装器当时提供的版本，未固定 Xray 版本。
- 已完成脚本语法与配置/连接生成等 12 项本地组件检查；尚未在真实 Ubuntu 服务器执行完整安装或验证客户端连接。服务启动成功不等于客户端连通性已验证。
