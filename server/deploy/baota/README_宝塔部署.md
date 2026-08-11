# 使用宝塔部署 CodexNotif Server

这份目录只包含示例，不应写入真实密码、Token、租户信息或证书私钥。

1. 在本地使用 Java 17 和 Maven 构建：`mvn -f server/app/pom.xml clean package`。
2. 将 `codexnotif-server.jar` 上传到 `<DEPLOY_DIR>`。
3. 在宝塔创建 Java 项目，启动命令为 `java -jar <DEPLOY_DIR>/codexnotif-server.jar`。
4. 在 Windows 仓库根目录运行 `powershell -ExecutionPolicy Bypass -File tools\Set-CodexNotifAccessKey.ps1`。脚本会生成高熵访问密钥，写入当前 Windows 用户环境变量并复制到剪贴板，但不会显示密钥。
5. 从本目录选择一份环境变量示例，复制到宝塔项目环境变量界面后替换占位符；将剪贴板内容粘贴为 `CODEXNOTIF_ACCESS_KEY`。它必须与 Windows 客户端环境变量完全一致，且不能与 `APP_ENCRYPTION_KEY`、`ADMIN_SETUP_TOKEN` 共用。
6. 确认服务只监听 `127.0.0.1:27843`，不要在安全组或防火墙公开该端口。
7. 创建站点 `notify.example.com`，申请 HTTPS 证书。
8. 把 `nginx-location.conf` 的内容放入站点配置，并重新加载 Nginx。
9. 重启 Java 项目；缺失或少于 32 个字符的 `CODEXNOTIF_ACCESS_KEY` 会让服务拒绝启动。
10. 使用可信 HTTP 工具请求 `/health`，并在 `X-CodexNotif-Access-Key` 请求头中加入访问密钥。不要把密钥直接写入命令历史或截图。
11. 完全退出并重新打开 CodexNotif 和 Codex，在桌面端“服务器设置”中确认“访问密钥：服务器验证通过”。

生产环境只允许客户端访问 HTTPS 域名。H2 数据文件应位于 `<DEPLOY_DIR>/data`，仅授予 Java 项目用户读写权限，并纳入加密备份。

如果服务器已经生成了访问密钥，可先把它复制到 Windows 剪贴板，再运行 `powershell -ExecutionPolicy Bypass -File tools\Set-CodexNotifAccessKey.ps1 -UseClipboard`。脚本只写入用户环境变量，不会把密钥保存到仓库、`settings.json` 或日志。
