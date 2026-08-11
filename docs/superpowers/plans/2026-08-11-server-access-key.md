# Server Access Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用两端同步的 `CODEXNOTIF_ACCESS_KEY` 保护服务器健康检查、绑定和事件 API，同时保留每设备 Device Token 二次认证。

**Architecture:** 服务端以失败关闭的访问密钥验证器和统一 Servlet 过滤器保护入口，并提供不泄露设备信息的认证检查接口。Windows 客户端只从环境变量读取访问密钥，每个请求都携带部署密钥头，事件请求额外携带 Bearer Device Token。

**Tech Stack:** Java 17、Spring Boot 3.4、JUnit 5、C# 12、.NET 8、WPF、现有自测试。

## Global Constraints

- 真实密钥只存在于服务器和 Windows 用户环境变量 `CODEXNOTIF_ACCESS_KEY`。
- 不把密钥写入源码、README、示例、日志、异常、`settings.json` 或 Git 历史。
- 不提交 `bin/`、`obj/`、`publish/`、`target/`、安装包、日志或本机配置。
- 访问密钥不少于 32 个字符，公网请求必须使用 HTTPS。
- `/api/v1/bind/verify` 保留一次性 Token 公开访问；其余 `/api/v1/**` 与 `/health` 必须验证访问密钥。
- 事件接口必须同时验证访问密钥与每设备 Device Token。

---

### Task 1: 服务端失败关闭验证器与过滤器

**Files:**
- Modify: `server/app/src/main/java/org/codexnotif/server/config/AppProperties.java`
- Modify: `server/app/src/main/resources/application.yml`
- Create: `server/app/src/main/java/org/codexnotif/server/security/AccessKeyValidator.java`
- Create: `server/app/src/main/java/org/codexnotif/server/security/AccessKeyFilter.java`
- Create: `server/app/src/test/java/org/codexnotif/server/security/AccessKeyValidatorTest.java`
- Create: `server/app/src/test/java/org/codexnotif/server/security/AccessKeyFilterTest.java`

**Interfaces:**
- Produces: `AccessKeyValidator.HEADER_NAME`、构造时失败关闭、`isValid(String)`。
- Produces: `AccessKeyFilter` 保护 `/health` 与 `/api/v1/**`，精确排除 `/api/v1/bind/verify`。

- [ ] **Step 1: 写服务端失败测试**

```java
@Test
void missingOrShortKeyFailsClosed() {
    AppProperties properties = new AppProperties();
    properties.setAccessKey("short");
    assertThrows(IllegalStateException.class,
            () -> new AccessKeyValidator(properties));
}

@Test
void protectedPathRejectsMissingKey() throws Exception {
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/health");
    MockHttpServletResponse response = new MockHttpServletResponse();
    filter.doFilter(request, response, new MockFilterChain());
    assertEquals(401, response.getStatus());
}
```

- [ ] **Step 2: 运行服务端测试并确认 RED**

Run: `mvn test`

Workdir: `server/app`

Expected: 编译失败，访问密钥类型尚不存在。

- [ ] **Step 3: 实现配置与常量时间验证**

```java
public final class AccessKeyValidator {
    public static final String HEADER_NAME = "X-CodexNotif-Access-Key";
    private final String expectedHash;

    public AccessKeyValidator(AppProperties properties) {
        String key = properties.getAccessKey();
        if (key == null || key.length() < 32 || !key.equals(key.trim())) {
            throw new IllegalStateException(
                    "CODEXNOTIF_ACCESS_KEY must contain at least 32 characters without surrounding whitespace.");
        }
        expectedHash = TokenUtil.sha256(key);
    }

    public boolean isValid(String supplied) {
        return supplied != null
                && !supplied.isBlank()
                && TokenUtil.constantTimeEquals(
                        expectedHash,
                        TokenUtil.sha256(supplied));
    }
}
```

`AppProperties` 增加 `accessKey` getter/setter，`application.yml` 绑定
`access-key: ${CODEXNOTIF_ACCESS_KEY:}`。

- [ ] **Step 4: 实现过滤器并运行 GREEN**

```java
protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request.getRequestURI();
    if ("/api/v1/bind/verify".equals(path)) return true;
    return !"/health".equals(path) && !path.startsWith("/api/v1/");
}
```

错误响应固定为 HTTP 401 JSON，不包含请求头值。补测正确密钥放行、错误密钥拒绝、
验证链接放行和其他 API 受保护。

Run: `mvn test`

Expected: 全部服务端测试 PASS。

- [ ] **Step 5: 本地提交服务端过滤器**

```powershell
git add -- server/app/src/main/java/org/codexnotif/server/config/AppProperties.java server/app/src/main/resources/application.yml server/app/src/main/java/org/codexnotif/server/security/AccessKeyValidator.java server/app/src/main/java/org/codexnotif/server/security/AccessKeyFilter.java server/app/src/test/java/org/codexnotif/server/security/AccessKeyValidatorTest.java server/app/src/test/java/org/codexnotif/server/security/AccessKeyFilterTest.java
git commit -m "feat: 增加服务器部署访问密钥"
```

### Task 2: 不泄露设备信息的认证检查接口

**Files:**
- Create: `server/app/src/main/java/org/codexnotif/server/model/AuthCheckResponse.java`
- Create: `server/app/src/main/java/org/codexnotif/server/controller/AuthController.java`
- Create: `server/app/src/test/java/org/codexnotif/server/controller/AuthControllerTest.java`

**Interfaces:**
- Consumes: Task 1 过滤器；现有 `DeviceService.validate` 与 `EventController.bearer`。
- Produces: `GET /api/v1/auth/check?deviceId=...` 返回 `accessKeyAuthenticated=true` 与 `deviceAuthenticated`。

- [ ] **Step 1: 写认证状态失败测试**

```java
@Test
void invalidOrMissingDeviceTokenDoesNotRevealExistence() {
    DeviceService devices = mock(DeviceService.class);
    when(devices.validate("D_TEST", "token")).thenReturn(false);
    AuthController controller = new AuthController(devices);
    AuthCheckResponse response = controller.check(
            "D_TEST", "Bearer token");
    assertTrue(response.accessKeyAuthenticated());
    assertFalse(response.deviceAuthenticated());
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `mvn test`

Workdir: `server/app`

Expected: 编译失败，认证控制器和响应尚不存在。

- [ ] **Step 3: 实现最小认证接口并运行 GREEN**

```java
@GetMapping("/check")
public AuthCheckResponse check(
        @RequestParam String deviceId,
        @RequestHeader(value = "Authorization", required = false)
        String authorization) {
    boolean authenticated = devices.validate(
            deviceId,
            EventController.bearer(authorization));
    return new AuthCheckResponse(true, authenticated);
}
```

测试有效与无效 Token 都只返回两个布尔字段，不返回邮箱、Token、哈希或存在状态。

Run: `mvn test`

Expected: 全部服务端测试 PASS。

- [ ] **Step 4: 本地提交认证接口**

```powershell
git add -- server/app/src/main/java/org/codexnotif/server/model/AuthCheckResponse.java server/app/src/main/java/org/codexnotif/server/controller/AuthController.java server/app/src/test/java/org/codexnotif/server/controller/AuthControllerTest.java
git commit -m "feat: 增加客户端认证状态接口"
```

### Task 3: Windows 客户端访问密钥与双层认证

**Files:**
- Create: `desktop/app/Services/ServerAccessKeyResolver.cs`
- Create: `desktop/app/Models/AuthCheckResponse.cs`
- Modify: `desktop/app/Services/RelayApiClient.cs`
- Modify: `desktop/app/App.xaml.cs`
- Modify: `desktop/app/MainWindow.xaml`
- Modify: `desktop/app/MainWindow.xaml.cs`
- Modify: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Produces: `ServerAccessKeyResolver.Read()` 与 `Validate(string?)`。
- Produces: `RelayApiClient(string, string?, HttpMessageHandler? = null)`、`HasValidAccessKey`、`CheckAuthenticationAsync`。

- [ ] **Step 1: 写客户端失败测试**

```csharp
Run("access key resolver rejects missing and short values", () =>
{
    AssertThrows<InvalidOperationException>(() =>
        ServerAccessKeyResolver.Validate("short"));
});

await RunAsync("relay sends access key and bearer token", async () =>
{
    var handler = new CaptureHttpHandler(
        "{\"accessKeyAuthenticated\":true,\"deviceAuthenticated\":true}");
    using var relay = new RelayApiClient(
        "https://notify.example.com",
        new string('x', 32),
        handler);
    await relay.CheckAuthenticationAsync("D_TEST", "device-token");
    Assert(handler.LastRequest!.Headers.Contains(
        ServerAccessKeyResolver.HeaderName),
        "request must contain access key header");
    Assert(handler.LastRequest.Headers.Authorization?.Scheme == "Bearer",
        "bound device check must contain bearer token");
});
```

- [ ] **Step 2: 运行自测试并确认 RED**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 编译失败，访问密钥解析器与认证模型尚不存在。

- [ ] **Step 3: 实现环境变量验证与统一请求头**

```csharp
public static string Read()
{
    return Validate(Environment.GetEnvironmentVariable(
        "CODEXNOTIF_ACCESS_KEY"));
}

public static string Validate(string? value)
{
    if (string.IsNullOrWhiteSpace(value)
        || value.Length < 32
        || !string.Equals(value, value.Trim(), StringComparison.Ordinal))
        throw new InvalidOperationException(
            "未配置有效的 CODEXNOTIF_ACCESS_KEY。请设置环境变量后重启程序。");
    return value;
}
```

`RelayApiClient` 在创建每个请求时先验证密钥，再添加
`X-CodexNotif-Access-Key`；事件与认证检查按需添加 Bearer Token。测试缺失密钥时
HTTP handler 调用次数保持 0。

- [ ] **Step 4: 接入前台、notify 与 Stop Hook**

前台显示“访问密钥已加载/未配置”，认证检查区分访问密钥通过与设备 Token 通过。
后台入口读取同一环境变量；缺失时只写固定错误类型。

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Run: `dotnet build desktop/app/AgentPager.csproj -c Release`

Expected: 自测试全部 PASS；构建 0 警告、0 错误。

- [ ] **Step 5: 本地提交客户端认证**

```powershell
git add -- desktop/app/Services/ServerAccessKeyResolver.cs desktop/app/Models/AuthCheckResponse.cs desktop/app/Services/RelayApiClient.cs desktop/app/App.xaml.cs desktop/app/MainWindow.xaml desktop/app/MainWindow.xaml.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "feat: 客户端同步服务器访问密钥"
```

### Task 4: 部署脚本、说明、审计与上传

**Files:**
- Create: `tools/Set-CodexNotifAccessKey.ps1`
- Modify: `server/deploy/baota/环境变量-MicrosoftGraph.example.txt`
- Modify: `server/deploy/baota/环境变量-SMTP备用.example.txt`
- Modify: `server/deploy/baota/README_宝塔部署.md`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-08-11-server-access-key.md`

**Interfaces:**
- Produces: 无参数生成 32 字节随机密钥、设置 Windows 用户环境变量并复制到剪贴板但不打印原文的脚本。
- Consumes: 两端同名 `CODEXNOTIF_ACCESS_KEY`。

- [ ] **Step 1: 实现不输出密钥的 Windows 脚本**

```powershell
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$key = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
[Environment]::SetEnvironmentVariable('CODEXNOTIF_ACCESS_KEY', $key, 'User')
Set-Clipboard -Value $key
Write-Host '访问密钥已写入 Windows 用户环境变量并复制到剪贴板。'
```

脚本支持 `-UseClipboard`，从剪贴板读取宝塔中已生成的同一密钥；两种模式都不得
将密钥写到标准输出、日志或文件。

- [ ] **Step 2: 更新宝塔示例与部署顺序**

两个示例文件只增加：

```text
CODEXNOTIF_ACCESS_KEY=<GENERATED_SECRET>
```

README 说明 Java 仅监听 127.0.0.1、只开放 HTTPS、两端同步、重启顺序、认证状态
含义以及密钥轮换会立即使旧值失效。

- [ ] **Step 3: 运行完整验证**

Run: `mvn test`

Workdir: `server/app`

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Run: `dotnet build desktop/app/AgentPager.csproj -c Release`

Expected: 两端测试全部 PASS；桌面构建 0 警告、0 错误。

- [ ] **Step 4: 三重脱敏与生成物门禁**

依次运行 Worktree、Index、History 三种 `tools/audit_public_repo.ps1` 审计；确认
`git ls-files` 不含生成目录、二进制、日志或本机配置；确认 TLS 验证为 `true`。

- [ ] **Step 5: 本地提交并在审计通过后上传**

```powershell
git add -- tools/Set-CodexNotifAccessKey.ps1 server/deploy/baota/环境变量-MicrosoftGraph.example.txt server/deploy/baota/环境变量-SMTP备用.example.txt server/deploy/baota/README_宝塔部署.md README.md docs/superpowers/plans/2026-08-11-server-access-key.md
git commit -m "docs: 完善访问密钥安全部署"
git push origin main
```

真实密钥只在上传完成后由脚本本机生成；设置 Windows 环境变量后不读取或输出其
值。宝塔端由用户粘贴剪贴板内容并重启服务，客户端与 Codex 随后重启。
