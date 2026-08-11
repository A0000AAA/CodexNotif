using System.Diagnostics;

namespace AgentPager.Services;

public static class CodexNotifyForwarder
{
    public static async Task RunAsync(
        IReadOnlyList<string> command,
        string payload,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        if (command.Count == 0
            || string.IsNullOrWhiteSpace(command[0]))
        {
            return;
        }

        var safeCommand = CodexNotifyCommand.CreateSafeForwardCommand(command);

        if (safeCommand.Length == 0)
        {
            TryLog(log, "已阻止原通知程序递归启动 CodexNotif。");
            return;
        }

        if (safeCommand.Length < command.Count)
            TryLog(log, "已移除原通知程序中的递归 CodexNotif 参数。");

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = safeCommand[0],
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            }
        };

        for (var index = 1; index < safeCommand.Length; index++)
            process.StartInfo.ArgumentList.Add(safeCommand[index]);

        process.StartInfo.ArgumentList.Add(payload);

        try
        {
            if (!process.Start())
                throw new InvalidOperationException(
                    "无法启动原通知程序。");

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));

            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                if (!process.HasExited)
                    process.Kill(entireProcessTree: true);

                throw new TimeoutException("原通知程序运行超时。");
            }
        }
        catch (Exception ex)
        {
            TryLog(log, $"原通知程序启动失败：{ex.GetType().Name}");
            throw;
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
            // Forwarding failures must never be promoted through diagnostics.
        }
    }
}
