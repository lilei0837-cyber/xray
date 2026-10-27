# Xray VLESS + REALITY 一键部署

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
