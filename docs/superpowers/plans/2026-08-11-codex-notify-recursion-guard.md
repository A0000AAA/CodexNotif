# Codex Notify Recursion Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 防止 Codex Desktop 通知包装器通过 `--previous-notify` 重复启动 CodexNotif。

**Architecture:** 新增一个无状态命令分析器，负责有界解析嵌套通知命令，并向配置识别与进程转发提供统一结果。配置层避免重复安装，转发层在保留包装器自身行为的同时删除递归参数。

**Tech Stack:** C# 12、.NET 8、WPF、现有控制台自测试。

## Global Constraints

- 只修改 `CodexNotif-Public`。
- 不增加第三方依赖，不记录通知 payload 或用户路径。
- 嵌套解析深度上限固定为 8。
- 保留非 CodexNotif 原通知程序与包装器行为。

---

### Task 1: 包装安装识别

**Files:**
- Create: `desktop/app/Services/CodexNotifyCommand.cs`
- Modify: `desktop/app/Services/CodexNotifyConfiguration.cs`
- Test: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Produces: `CodexNotifyCommand.TargetsExecutable(IReadOnlyList<string>, string)` 返回命令是否直接或嵌套指向当前可执行文件。

- [x] **Step 1: 写入失败回归测试**

```csharp
var previous = JsonSerializer.Serialize(new[] { executable, "--codex-notify" });
var wrapper = JsonSerializer.Serialize(new[]
{
    "codex-computer-use.exe", "turn-ended", "--previous-notify", previous
});
File.WriteAllText(config, "notify = " + wrapper + "\n");
Assert(CodexNotifyConfiguration.GetStatus(config, executable)
       == CodexNotifyConfigurationStatus.Installed,
       "wrapped CodexNotif command must be Installed");
```

- [x] **Step 2: 运行测试并确认旧实现失败**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: FAIL，包装器被报告为 `Missing`。

- [x] **Step 3: 实现有界命令识别**

```csharp
public static bool TargetsExecutable(
    IReadOnlyList<string> command,
    string executablePath)
{
    return TargetsExecutable(command, executablePath, depth: 0);
}
```

解析每个 `--previous-notify` 后的 JSON 字符串数组；直接命令同时满足可执行文件
路径相同且包含 `--codex-notify`。深度达到 8 或 JSON 无效时返回 `false`。

- [x] **Step 4: 让配置层复用识别器并运行测试**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: 新测试与既有测试全部 PASS。

- [x] **Step 5: 提交配置识别修复**

```powershell
git add -- desktop/app/Services/CodexNotifyCommand.cs desktop/app/Services/CodexNotifyConfiguration.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "fix: 识别包装器中的 Codex 通知命令"
```

### Task 2: 运行时递归防护

**Files:**
- Modify: `desktop/app/Services/CodexNotifyCommand.cs`
- Modify: `desktop/app/Services/CodexNotifyForwarder.cs`
- Test: `desktop/tests/AgentPager.SelfTests/Program.cs`

**Interfaces:**
- Consumes: Task 1 的嵌套 JSON 解析。
- Produces: `CodexNotifyCommand.CreateSafeForwardCommand(IReadOnlyList<string>)` 返回可以安全启动的参数数组，直接 CodexNotif 命令返回空数组。

- [x] **Step 1: 写入失败转发测试**

```csharp
if (args is ["--capture-arguments", var capturePath, .. var captured])
{
    File.WriteAllText(capturePath, JsonSerializer.Serialize(captured));
    return 0;
}

await CodexNotifyForwarder.RunAsync(
    new[] { Environment.ProcessPath!, "--capture-arguments", capturePath,
            "--previous-notify", nestedCodexNotif },
    payload, _ => { }, CancellationToken.None);
Assert(JsonSerializer.Deserialize<string[]>(File.ReadAllText(capturePath))!
           .SequenceEqual(new[] { payload }),
       "recursive previous-notify pair must be removed before forwarding");
```

- [x] **Step 2: 运行测试并确认旧实现失败**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Expected: FAIL，因为捕获进程收到 `--previous-notify` 而不是 payload。

- [x] **Step 3: 实现净化并接入转发器**

```csharp
var safeCommand = CodexNotifyCommand.CreateSafeForwardCommand(command);
if (safeCommand.Count == 0)
{
    TryLog(log, "已阻止原通知程序递归启动 CodexNotif。");
    return;
}
```

逐项复制命令；仅当 `--previous-notify` 后的 JSON 数组包含
`--codex-notify` 时跳过该参数对。

- [x] **Step 4: 运行全部桌面端验证**

Run: `dotnet run --project desktop/tests/AgentPager.SelfTests/AgentPager.SelfTests.csproj`

Run: `dotnet build desktop/app/AgentPager.csproj -c Release`

Expected: 两条命令均以退出码 0 完成。

- [x] **Step 5: 提交运行时修复**

```powershell
git add -- desktop/app/Services/CodexNotifyCommand.cs desktop/app/Services/CodexNotifyForwarder.cs desktop/tests/AgentPager.SelfTests/Program.cs
git commit -m "fix: 阻止 Codex 完成通知递归转发"
```

### Task 3: 发布前审查

**Files:**
- Modify: `README.md`（仅在需要说明兼容行为时）

**Interfaces:**
- Consumes: Task 1 与 Task 2 的全部实现和测试结果。
- Produces: 可公开推送的无敏感信息提交。

- [x] **Step 1: 检查差异与敏感信息**

Run: `git diff --check`

Run: `rg -n -i "(password|secret|token|api[_-]?key|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|192\\.168\\.|10\\.[0-9]+\\.)" --glob '!**/bin/**' --glob '!**/obj/**' .`

Expected: 没有真实凭据、私有地址或私钥；测试占位符必须使用 `.test` 或示例值。

- [x] **Step 2: 检查提交与远端 TLS**

Run: `git status --short --branch`

Run: `git config --get-urlmatch http.sslVerify https://github.com/`

Expected: 仅包含计划内改动，TLS 输出为 `true`。

- [ ] **Step 3: 推送主分支**

Run: `git push origin main`

Expected: `main -> main`，且没有 TLS 验证关闭警告。
