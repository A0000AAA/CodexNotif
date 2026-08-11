# Access Key UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 客户端服务器设置中安全输入并保存 `CODEXNOTIF_ACCESS_KEY`，无需用户手工运行环境变量脚本。

**Architecture:** `ServerAccessKeyResolver` 继续作为唯一密钥入口，新增用户环境变量保存与 Process/User 两级读取。WPF 服务器设置使用不回填的 `PasswordBox`，现有“保存并测试”同时保存可选新密钥并调用认证接口。

**Tech Stack:** C# 12、.NET 8、WPF、现有控制台自测试、PowerShell 脱敏审计。

## Global Constraints

- 密钥不写入 `AppSettings`、`settings.json`、日志、异常、README 示例值或 Git 历史。
- 密钥框使用 `PasswordBox`，启动时永远不回填真实值。
- 留空保留现有密钥；新值不少于 32 个字符且不含空白或控制字符。
- 服务端继续通过宝塔环境变量配置相同的 `CODEXNOTIF_ACCESS_KEY`。
- 不提交 `bin/`、`obj/`、`publish/`、`target/` 或安装包。

---

### Task 1: 环境变量保存与读取

**Files:**
- Modify: `desktop/app/Services/ServerAccessKeyResolver.cs`
- Modify: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Produces: `ServerAccessKeyResolver.SaveForCurrentUser(string)`。
- Changes: `ReadOptional()` 优先读取 Process，再回退 User。

- [ ] **Step 1: Write the failing process-precedence test**

```csharp
Run("access key resolver prefers current process value", () =>
{
    var previous = Environment.GetEnvironmentVariable(
        ServerAccessKeyResolver.EnvironmentVariableName,
        EnvironmentVariableTarget.Process);
    try
    {
        var expected = new string('p', 32);
        Environment.SetEnvironmentVariable(
            ServerAccessKeyResolver.EnvironmentVariableName,
            expected,
            EnvironmentVariableTarget.Process);
        Assert(ServerAccessKeyResolver.ReadOptional() == expected,
            "process access key must win");
    }
    finally
    {
        Environment.SetEnvironmentVariable(
            ServerAccessKeyResolver.EnvironmentVariableName,
            previous,
            EnvironmentVariableTarget.Process);
    }
});

Run("access key save rejects invalid values before persistence", () =>
{
    AssertThrows<InvalidOperationException>(() =>
        ServerAccessKeyResolver.SaveForCurrentUser("short"));
});
```

- [ ] **Step 2: Run the self-tests and verify RED**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 编译失败，因为 `SaveForCurrentUser` 尚不存在；Process 测试同时记录新的读取契约。

- [ ] **Step 3: Implement environment persistence**

```csharp
public static string? ReadOptional()
{
    return Environment.GetEnvironmentVariable(
               EnvironmentVariableName,
               EnvironmentVariableTarget.Process)
           ?? Environment.GetEnvironmentVariable(
               EnvironmentVariableName,
               EnvironmentVariableTarget.User);
}

public static void SaveForCurrentUser(string value)
{
    string key = Validate(value);
    Environment.SetEnvironmentVariable(
        EnvironmentVariableName,
        key,
        EnvironmentVariableTarget.User);
    Environment.SetEnvironmentVariable(
        EnvironmentVariableName,
        key,
        EnvironmentVariableTarget.Process);
}
```

- [ ] **Step 4: Run self-tests and verify GREEN**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 全部自测试通过，测试结束后恢复原 Process 环境变量。

- [ ] **Step 5: Commit**

```powershell
git add -- desktop/app/Services/ServerAccessKeyResolver.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "feat: 增加访问密钥环境变量保存"
```

### Task 2: 遮罩界面、保存流程与文档

**Files:**
- Modify: `desktop/app/MainWindow.xaml`
- Modify: `desktop/app/MainWindow.xaml.cs`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ServerAccessKeyResolver.SaveForCurrentUser(string)`。
- Produces: `AccessKeyPasswordBox`，由 `SaveServerButton_Click` 读取但从不回填。

- [ ] **Step 1: Add the masked input**

```xml
<TextBlock Margin="0,12,0,0" Text="服务器访问密钥"/>
<PasswordBox x:Name="AccessKeyPasswordBox"
             Margin="0,7,0,0"
             ToolTip="留空表示继续使用当前环境变量中的密钥"/>
<TextBlock Margin="0,5,0,0"
           Text="留空保留现有值；新值只写入 Windows 用户环境变量。"
           TextWrapping="Wrap"/>
```

- [ ] **Step 2: Save an optional new key before replacing the relay**

```csharp
var enteredAccessKey = AccessKeyPasswordBox.Password;
if (!string.IsNullOrEmpty(enteredAccessKey))
{
    ServerAccessKeyResolver.SaveForCurrentUser(enteredAccessKey);
    AccessKeyPasswordBox.Clear();
}
```

校验或环境变量写入失败时由现有异常处理显示固定错误；不把 `enteredAccessKey` 拼入任何消息。保存成功后 `ReplaceRelay` 读取新的 Process 值，并由 `CheckServerAsync` 验证服务端是否同步。

- [ ] **Step 3: Update usage documentation**

README 说明可直接在遮罩框粘贴宝塔同名密钥并点击“保存并测试”；脚本保留为无人值守和批量部署方案。明确密钥框留空不会删除现值，修改后无需把密钥写入 `settings.json`。

- [ ] **Step 4: Verify desktop build and tests**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Run: `dotnet build desktop/app/AgentPager.csproj -c Release`

Expected: 自测试全部通过；Release 构建 0 警告、0 错误。

- [ ] **Step 5: Audit, commit and push**

依次运行 Worktree、Index、History 脱敏审计，确认无生成物跟踪且 TLS 校验为 `true`，然后提交：

```powershell
git add -- desktop/app/MainWindow.xaml desktop/app/MainWindow.xaml.cs README.md
git commit -m "feat: 支持在界面配置服务器访问密钥"
git push origin main
```
