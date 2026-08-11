using System.Text.Json;
using AgentPager.Models;

namespace AgentPager.Services;

public static class CodexNotifyRunner
{
    public static async Task RunAsync(
        string payload,
        string deviceId,
        AppSettings settings,
        Func<AgentEvent, string, CancellationToken, Task> sendEvent,
        Func<string, CancellationToken, Task> forward,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);

            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty(
                    "type",
                    out var typeElement)
                || !string.Equals(
                    typeElement.GetString(),
                    "agent-turn-complete",
                    StringComparison.Ordinal))
            {
                TryLog(log, "收到非 Codex 主任务完成事件，已忽略。");
                return;
            }
        }
        catch (JsonException)
        {
            TryLog(log, "Codex notify 输入不是有效 JSON，已忽略。");
            return;
        }

        var forwardTask = RunSafelyAsync(
            token => forward(payload, token),
            "原通知程序转发",
            log,
            cancellationToken);

        Task mailTask;

        if (string.IsNullOrWhiteSpace(settings.DeviceToken)
            || string.IsNullOrWhiteSpace(settings.BoundEmail))
        {
            TryLog(log, "收到 Codex 完成事件，但设备尚未绑定通知邮箱。");
            mailTask = Task.CompletedTask;
        }
        else
        {
            var agentEvent = new AgentEvent(
                deviceId,
                "codex",
                "agent.completed",
                DateTimeOffset.Now);

            mailTask = RunSafelyAsync(
                token => sendEvent(
                    agentEvent,
                    settings.DeviceToken,
                    token),
                "Codex 完成邮件提交",
                log,
                cancellationToken);
        }

        await Task.WhenAll(mailTask, forwardTask);
    }

    private static async Task RunSafelyAsync(
        Func<CancellationToken, Task> action,
        string operation,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        try
        {
            await action(cancellationToken);
            TryLog(log, operation + "成功。");
        }
        catch (Exception ex)
        {
            TryLog(log, $"{operation}失败：{ex.GetType().Name}");
        }
    }

    private static void TryLog(
        Action<string> log,
        string message)
    {
        try
        {
            log(message);
        }
        catch
        {
            // Diagnostics must not break either notification destination.
        }
    }
}
