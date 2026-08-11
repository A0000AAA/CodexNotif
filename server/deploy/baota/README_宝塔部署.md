# 使用宝塔部署 CodexNotif Server

这份目录只包含示例，不应写入真实密码、Token、租户信息或证书私钥。

1. 在本地使用 Java 17 和 Maven 构建：`mvn -f server/app/pom.xml clean package`。
2. 将 `codexnotif-server.jar` 上传到 `<DEPLOY_DIR>`。
3. 在宝塔创建 Java 项目，启动命令为 `java -jar <DEPLOY_DIR>/codexnotif-server.jar`。
4. 从本目录选择一份环境变量示例，复制到宝塔项目环境变量界面后替换占位符。
5. 确认服务只监听 `127.0.0.1:27843`，不要在安全组或防火墙公开该端口。
6. 创建站点 `notify.example.com`，申请 HTTPS 证书。
7. 把 `nginx-location.conf` 的内容放入站点配置，并重新加载 Nginx。
8. 在服务器执行 `curl http://127.0.0.1:27843/health`。
9. 在客户端执行 `curl https://notify.example.com/health`。

生产环境只允许客户端访问 HTTPS 域名。H2 数据文件应位于 `<DEPLOY_DIR>/data`，仅授予 Java 项目用户读写权限，并纳入加密备份。
