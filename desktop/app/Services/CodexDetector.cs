using AgentPager.Models;

namespace AgentPager.Services;

/// <summary>
/// 目前仍是 P0 占位检测器。
/// 邮箱绑定、Device Token 和服务端链路已经是真实的。
/// 下一步只需要把这里替换成真正的非侵入式 Codex 完成检测。
/// </summary>
public sealed class CodexDetector
{
    private readonly string _deviceId;

    public CodexDetector(string deviceId)
    {
        _deviceId = deviceId;
    }

    public bool IsRunning { get; private set; }

    public event EventHandler<AgentEvent>? Completed;

    public void Start()
    {
        IsRunning = true;
    }

    public void Stop()
    {
        IsRunning = false;
    }

    public void SimulateCompleted()
    {
        if (!IsRunning)
            return;

        Completed?.Invoke(
            this,
            new AgentEvent(
                _deviceId,
                "codex",
                "agent.completed",
                DateTimeOffset.Now));
    }
}
