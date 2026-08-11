# Desktop Server Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 CodexNotif 桌面客户端中提供持久化服务器地址设置，并让前台与后台通知使用同一解析结果。

**Architecture:** 新增无状态 `ServerAddressResolver` 负责验证、规范化、优先级和来源；`RelayApiClient` 只接收解析后的地址，不再自行读取环境变量。`AppSettings` 持久化用户选择，WPF 窗口和后台入口分别加载同一设置并构造 API 客户端。

**Tech Stack:** C# 12、.NET 8、WPF、System.Text.Json、现有控制台自测试。

## Global Constraints

- 不增加第三方依赖。
- 不提交 `bin/`、`obj/`、`publish/`、安装包、日志或本机配置。
- 不提交真实服务器地址、邮箱、Token、证书、个人路径或其他个人信息。
- 地址优先级固定为客户端设置、`CODEXNOTIF_SERVER_URL`、`http://localhost:27843`。
- 修改服务器地址不得清除邮箱绑定、Device Token 或待验证状态。

---

### Task 1: 地址解析与 API 客户端

**Files:**
- Create: `desktop/app/Services/ServerAddressResolver.cs`
- Modify: `desktop/app/Services/RelayApiClient.cs`
- Test: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Produces: `ServerAddressResolver.Normalize(string)`、`ServerAddressResolver.Resolve(string?, string?)`、`ServerAddressResolution`、`ServerAddressSource`。
- Produces: `RelayApiClient(string serverBaseUrl)` 和实例属性 `ServerBaseUrl`。

- [x] **Step 1: 写入地址解析失败测试**

```csharp
Run("saved server URL wins and invalid URLs are rejected", () =>
{
    var resolved = ServerAddressResolver.Resolve(
        " https://notify.example.com/base/ ",
        "https://notify.example.com/environment");
    Assert(resolved.BaseUrl == "https://notify.example.com/base",
        "saved URL must win and normalize");
    Assert(resolved.Source == ServerAddressSource.ClientSettings,
        "saved URL source must be reported");
    AssertThrows<ArgumentException>(() =>
        ServerAddressResolver.Normalize("ftp://notify.example.com"));
});
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 编译失败，`ServerAddressResolver` 尚不存在。

- [x] **Step 3: 实现解析器与显式 API 地址**

```csharp
public enum ServerAddressSource
{
    ClientSettings,
    EnvironmentVariable,
    BuiltInDefault
}

public sealed record ServerAddressResolution(
    string BaseUrl,
    ServerAddressSource Source);

public static ServerAddressResolution Resolve(
    string? savedBaseUrl,
    string? environmentBaseUrl)
{
    if (!string.IsNullOrWhiteSpace(savedBaseUrl))
        return new(Normalize(savedBaseUrl), ServerAddressSource.ClientSettings);
    if (!string.IsNullOrWhiteSpace(environmentBaseUrl))
        return new(Normalize(environmentBaseUrl), ServerAddressSource.EnvironmentVariable);
    return new(DefaultBaseUrl, ServerAddressSource.BuiltInDefault);
}

public static ServerAddressResolution Resolve(string? savedBaseUrl)
{
    return Resolve(
        savedBaseUrl,
        Environment.GetEnvironmentVariable("CODEXNOTIF_SERVER_URL"));
}
```

`Normalize` 使用 `Uri.TryCreate(..., UriKind.Absolute, ...)`，只允许 HTTP(S)、
非空主机、空 `UserInfo`、空 `Query`、空 `Fragment`，并去掉末尾 `/`。
`RelayApiClient` 构造函数保存规范化后的实例地址，所有请求使用该属性。

- [x] **Step 4: 补齐优先级与非法地址测试并运行 GREEN**

```csharp
Assert(
    ServerAddressResolver.Resolve(null, "https://notify.example.com/environment/")
        == new ServerAddressResolution(
            "https://notify.example.com/environment",
            ServerAddressSource.EnvironmentVariable),
    "empty saved URL must use the environment");
Assert(
    ServerAddressResolver.Resolve("", "").BaseUrl
        == "http://localhost:27843",
    "empty saved and environment URLs must use the default");
foreach (var invalid in new[]
         {
             "relative/path",
             "ftp://notify.example.com",
             "http://localhost@localhost",
             "https://notify.example.com?token=value",
             "https://notify.example.com/#fragment"
         })
{
    AssertThrows<ArgumentException>(() =>
        ServerAddressResolver.Normalize(invalid));
}
```

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 全部测试 PASS。

- [x] **Step 5: 本地提交解析器**

```powershell
git add -- desktop/app/Services/ServerAddressResolver.cs desktop/app/Services/RelayApiClient.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "feat: 增加桌面端服务器地址解析"
```

### Task 2: 设置持久化与前后台统一

**Files:**
- Modify: `desktop/app/Models/AppSettings.cs`
- Modify: `desktop/app/Services/SettingsService.cs`
- Modify: `desktop/app/App.xaml.cs`
- Modify: `desktop/app/MainWindow.xaml.cs`
- Test: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Consumes: Task 1 的 `ServerAddressResolver` 与 `RelayApiClient(string)`。
- Produces: `AppSettings.ServerBaseUrl`；`SettingsService(string? path = null)` 支持默认本地路径与可测试的显式路径。

- [x] **Step 1: 写入设置往返失败测试**

```csharp
Run("server URL persists without changing binding data", () =>
{
    using var temp = new TempDirectory();
    var service = new SettingsService(Path.Combine(temp.Path, "settings.json"));
    var settings = BoundSettings();
    settings.PendingBindId = "B_TEST";
    settings.ServerBaseUrl = "https://notify.example.com";
    service.Save(settings);
    var loaded = service.Load();
    Assert(loaded.ServerBaseUrl == settings.ServerBaseUrl,
        "server URL must persist");
    Assert(loaded.DeviceToken == settings.DeviceToken
           && loaded.BoundEmail == settings.BoundEmail
           && loaded.PendingBindId == settings.PendingBindId,
        "binding data must remain intact");
});
```

- [x] **Step 2: 运行测试并确认 RED**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 编译失败，模型字段和显式设置路径尚不存在。

- [x] **Step 3: 实现模型、持久化和后台入口**

```csharp
public string ServerBaseUrl { get; set; } = "";

public SettingsService(string? path = null)
{
    if (!string.IsNullOrWhiteSpace(path))
    {
        _path = Path.GetFullPath(path);
        return;
    }

    var directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexNotif");
    Directory.CreateDirectory(directory);
    _path = Path.Combine(directory, "settings.json");
}
```

`Save` 在写文件前创建显式路径的父目录。`App.RunNotifyAsync` 与
`RunStopHookAsync` 使用以下相同结构加载一次设置：

```csharp
var settings = new SettingsService().Load();
var server = ServerAddressResolver.Resolve(settings.ServerBaseUrl);
using var relay = new RelayApiClient(server.BaseUrl);
```

随后将同一 `settings` 传给现有 Runner。

- [x] **Step 4: 让窗口构造使用同一解析结果并运行 GREEN**

将 `MainWindow._relay` 改为构造函数中在加载 `_settings` 后初始化，并把现有
静态 `RelayApiClient.ServerBaseUrl` 显示改为实例 `_relay.ServerBaseUrl`。

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 全部测试 PASS。

- [x] **Step 5: 本地提交持久化与统一入口**

```powershell
git add -- desktop/app/Models/AppSettings.cs desktop/app/Services/SettingsService.cs desktop/app/App.xaml.cs desktop/app/MainWindow.xaml.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "feat: 统一前后台服务器配置"
```

### Task 3: WPF 设置界面、文档与发布审计

**Files:**
- Modify: `desktop/app/MainWindow.xaml`
- Modify: `desktop/app/MainWindow.xaml.cs`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 和 Task 2 的地址解析、持久化和可替换 `_relay`。
- Produces: `SaveServerButton_Click`、`RestoreServerButton_Click`、`ReplaceRelay` 和可见服务器配置卡片。

- [x] **Step 1: 增加服务器设置卡片**

```xml
<TextBox x:Name="ServerUrlTextBox"/>
<Button Content="保存并测试" Click="SaveServerButton_Click"/>
<Button Content="恢复默认" Click="RestoreServerButton_Click"/>
<TextBlock x:Name="ServerSettingsStatusText" TextWrapping="Wrap"/>
```

卡片放在主区左列、邮箱绑定卡片之前，并复用现有 `CardStyle`、主按钮和次按钮样式。

- [x] **Step 2: 实现保存、恢复和连接结果**

```csharp
private async void SaveServerButton_Click(object sender, RoutedEventArgs e)
{
    try
    {
        var normalized = ServerAddressResolver.Normalize(
            ServerUrlTextBox.Text);
        _settings.ServerBaseUrl = normalized;
        _settingsService.Save(_settings);
        ReplaceRelay(ServerAddressResolver.Resolve(
            _settings.ServerBaseUrl));
        var ok = await CheckServerAsync();
        ServerSettingsStatusText.Text = ok
            ? "服务器设置已保存，连接正常。"
            : "服务器设置已保存，但当前无法连接。";
    }
    catch (ArgumentException ex)
    {
        ServerSettingsStatusText.Text = ex.Message;
    }
}
```

捕获 `ArgumentException` 时显示格式原因且不保存。恢复按钮清空保存值，重建客户端
并检查。`CheckServerAsync` 返回 `bool`，保持现有顶部状态和事件记录行为。

- [x] **Step 3: 更新 README**

说明 GUI 配置路径、三层优先级、环境变量回退、后台生效需重启 Codex；所有示例
只使用 `https://notify.example.com`，不得写入真实地址。

- [x] **Step 4: 运行完整验证与三重脱敏审计**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Run: `dotnet build desktop/app/AgentPager.csproj -c Release`

Run: `git diff --check`

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit_public_repo.ps1 -Scope Worktree`

暂存源码、测试、README 和计划文件后运行：

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit_public_repo.ps1 -Scope Index`

提交后运行：

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/audit_public_repo.ps1 -Scope History`

Expected: 测试全部 PASS；构建 0 警告、0 错误；三次审计均 `PASS: no blocked public data`；Git 中没有构建产物。

- [ ] **Step 5: 本地提交并在审计通过后上传**

```powershell
git add -- desktop/app/MainWindow.xaml desktop/app/MainWindow.xaml.cs README.md docs/superpowers/plans/2026-08-11-desktop-server-settings.md
git commit -m "feat: 增加桌面端服务器设置界面"
git push origin main
```

上传前再次确认 `git status --short --ignored` 中生成目录均以 `!!` 显示，且
`git ls-files` 不包含 `bin/`、`obj/`、`publish/`、安装包、日志或本机配置。
