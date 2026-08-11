# 服务器访问密钥设计

## 背景与威胁

CodexNotif 已使用每设备 `DeviceToken` 保护事件接口，但首次邮箱绑定接口只依赖
IP 限流。公网入口被扫描后，陌生人虽然不能伪造已绑定设备事件，仍可能尝试调用
绑定接口发送验证邮件。公开端口本身无法靠“隐藏端口”获得可靠安全性，需要在
TLS、反向代理、部署级访问密钥和每设备凭据之间建立分层防护。

## 目标

- 只有持有当前部署访问密钥的客户端才能调用健康检查和功能 API。
- 事件接口同时验证部署访问密钥与每设备 `DeviceToken`。
- 访问密钥只存在于服务器和 Windows 客户端的环境变量中。
- 服务端缺少有效密钥时拒绝启动，客户端缺少密钥时不发送网络请求。
- 不把真实密钥写入源码、README、示例、日志、异常、`settings.json` 或 Git 历史。

## 非目标

- 不使用固定编译进客户端的公共密钥。
- 不实现 HMAC 请求签名、Nonce、密钥轮换窗口或双向 TLS。
- 不替代 HTTPS、宝塔/Nginx 防火墙规则、现有限流或每设备 Token。
- 不改变移动端；移动端仍通过邮箱接收通知，不直接调用服务器 API。

## 凭据分工

### 部署访问密钥

服务器和 Windows 客户端使用同名环境变量：

```text
CODEXNOTIF_ACCESS_KEY=<GENERATED_SECRET>
```

该密钥证明请求来自被部署者授权的客户端实例。密钥使用 32 字节安全随机数生成，
编码后不得少于 32 个字符。服务端只在内存中读取；客户端只在进程环境中读取。

客户端通过以下请求头发送：

```text
X-CodexNotif-Access-Key: <GENERATED_SECRET>
```

只允许通过 HTTPS 向公网发送该请求头。

### 每设备 Device Token

邮箱验证成功后，服务器继续为每台设备生成独立 `DeviceToken`。事件请求同时发送：

```text
Authorization: Bearer <DEVICE_TOKEN>
```

部署访问密钥验证“是否属于这套部署”，Device Token 验证“是哪台已绑定设备”。
任意一层失败都拒绝事件。

### 服务器专用密钥

`APP_ENCRYPTION_KEY` 继续只用于服务器数据库字段加密；`ADMIN_SETUP_TOKEN`
继续只用于管理接口。二者都不得同步到客户端，也不得与部署访问密钥复用。

## 服务端设计

### 配置与失败关闭

在 `AppProperties` 增加 `accessKey`，由以下配置绑定：

```yaml
app:
  access-key: ${CODEXNOTIF_ACCESS_KEY:}
```

新增启动校验：值为空或少于 32 个字符时抛出启动错误。错误只说明环境变量缺失或
长度不足，不包含密钥内容。这样新版本不会在漏配密钥时以开放模式运行。

### 统一过滤器

新增基于 `OncePerRequestFilter` 的 `AccessKeyFilter`。过滤器读取
`X-CodexNotif-Access-Key`，对期望值和请求值分别做 SHA-256，再使用
`MessageDigest.isEqual` 对等长摘要进行常量时间比较。

保护范围：

- `/health`；
- `/api/v1/**`；
- 例外：`/api/v1/bind/verify`。

密钥缺失或错误时返回 HTTP 401 与固定 JSON 消息，不区分“缺失”和“错误”，
不记录请求头值。邮件验证链接保留公开，因为普通浏览器无法携带环境变量密钥；
该链接仍由高强度一次性 `verifyToken`、绑定 ID 和过期时间保护。

管理接口继续由 `ADMIN_SETUP_TOKEN` 独立保护，不复用访问密钥。

### 认证状态接口

新增：

```text
GET /api/v1/auth/check?deviceId=<DEVICE_ID>
```

过滤器先验证部署访问密钥。控制器再读取可选的 Bearer Device Token：

- 访问密钥正确且设备 Token 正确：返回 `deviceAuthenticated=true`；
- 访问密钥正确但尚未绑定或 Token 无效：返回
  `deviceAuthenticated=false`，不泄露设备是否存在；
- 访问密钥错误：过滤器返回 401，控制器不执行。

响应不得返回邮箱、Token、哈希或其他设备详情。

## Windows 客户端设计

### 环境变量读取

新增 `ServerAccessKeyResolver`，只读取 `CODEXNOTIF_ACCESS_KEY`。值为空或少于
32 个字符时返回明确的本地配置错误。该值不加入 `AppSettings`，不写
`settings.json`，不在界面显示原文。

### 请求行为

`RelayApiClient` 构造时接收服务器地址与访问密钥。健康检查、认证检查、绑定创建、
绑定轮询和事件请求全部携带 `X-CodexNotif-Access-Key`；事件及已绑定设备操作继续
携带 Bearer Device Token。

客户端缺少有效环境变量时，在构造网络请求前失败。后台 notify 和 Stop Hook 只记录
固定错误类型，不记录密钥、Device Token、邮箱或通知正文。

### 界面

服务器设置卡片增加只读状态：

- `访问密钥：已从环境变量加载`；或
- `访问密钥：未配置 CODEXNOTIF_ACCESS_KEY`。

界面不提供密钥输入框。“保存并测试”改为调用认证状态接口，并分别显示：

- 服务器访问密钥验证通过；
- 设备认证通过；
- 服务器访问密钥通过，但需要绑定或重新绑定邮箱；
- 访问密钥被服务器拒绝。

修改用户级环境变量后必须完全退出并重新打开 CodexNotif；后台通知还需要重启
Codex，确保新进程继承环境变量。

## 部署要求

- Java 服务继续监听 `127.0.0.1:27843`，不得直接暴露到公网。
- 宝塔/Nginx 只向公网开放 HTTPS，代理到本机 Java 端口。
- 在宝塔 Java 项目环境变量与 Windows 用户环境变量中写入完全相同的
  `CODEXNOTIF_ACCESS_KEY`。
- 环境变量示例文件只写 `<GENERATED_SECRET>`，不得写真实值。
- 先准备同一密钥，再更新并重启服务端，随后重启客户端和 Codex，避免长期中断。
- 更换密钥时必须同步更新两端并重启；旧密钥立即失效。

## 测试

### 服务端

- 缺少、空白或短密钥时启动校验失败；
- 正确密钥通过过滤器；
- 缺失或错误密钥返回 401；
- `/health` 与 `/api/v1/**` 被保护；
- 邮件验证链接跳过部署访问密钥过滤器；
- 认证检查不泄露邮箱、Token 或设备是否存在；
- 事件接口仍要求有效 Device Token。

### 客户端

- 环境变量缺失、空白或过短时在发请求前失败；
- 所有 API 请求携带访问密钥请求头；
- 事件请求同时携带访问密钥和 Bearer Device Token；
- 认证状态正确区分已认证与需要绑定；
- 日志和界面不显示密钥原文；
- 既有服务器地址、绑定和通知递归回归测试继续通过。

### 发布门禁

运行服务端测试、桌面端自测试、Release 构建，以及工作区、暂存区和完整 Git 历史
三重脱敏审计。确认 `bin/`、`obj/`、`publish/`、`target/`、日志和本机配置仍未被
Git 跟踪后才能上传。
