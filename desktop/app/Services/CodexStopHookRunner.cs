using System.IO;
using System.Text.Json;
using AgentPager.Models;

namespace AgentPager.Services;

public static class CodexStopHookRunner
{
    public static async Task RunAsync(
        TextReader input,
        TextWriter output,
        string deviceId,
        AppSettings settings,
        Func<AgentEvent, string, CancellationToken, Task> sendEvent,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        try
        {
            var json = await input.ReadToEndAsync(cancellationToken);
            using var document = JsonDocument.Parse(json);

            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                TryLog(log, "Hook 输入不是 JSON 对象，已忽略。");
                return;
            }

            var eventName = document.RootElement.TryGetProperty(
                "hook_event_name",
                out var eventNameElement)
                ? eventNameElement.GetString()
                : null;

            if (!string.Equals(eventName, "Stop", StringComparison.Ordinal))
            {
                TryLog(log, "收到非 Stop Hook，已忽略。");
                return;
            }

            if (string.IsNullOrWhiteSpace(settings.DeviceToken)
                || string.IsNullOrWhiteSpace(settings.BoundEmail))
            {
                TryLog(log, "收到 Stop Hook，但设备尚未绑定通知邮箱。");
                return;
            }

            var agentEvent = new AgentEvent(
                deviceId,
                "codex",
                "agent.completed",
                DateTimeOffset.Now);

            await sendEvent(
                agentEvent,
                settings.DeviceToken,
                cancellationToken);

            TryLog(log, "Codex Stop 完成通知已提交。");
        }
        catch (JsonException)
        {
            TryLog(log, "Hook 输入不是有效 JSON，已忽略。");
        }
        catch (Exception ex)
        {
            TryLog(
                log,
                $"Codex Stop 通知处理失败：{ex.GetType().Name}");
        }
        finally
        {
            await output.WriteAsync("{\"continue\":true}");
            await output.FlushAsync();
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
            // Diagnostics must never break or delay the Codex Stop response.
        }
    }
}
