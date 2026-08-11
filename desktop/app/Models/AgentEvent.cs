namespace AgentPager.Models;

public sealed record AgentEvent(
    string DeviceId,
    string Source,
    string EventType,
    DateTimeOffset Timestamp);
