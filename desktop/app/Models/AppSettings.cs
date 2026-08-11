namespace AgentPager.Models;

public sealed class AppSettings
{
    public string ServerBaseUrl { get; set; } = "";

    public string DeviceToken { get; set; } = "";
    public string BoundEmail { get; set; } = "";

    public string PendingBindId { get; set; } = "";
    public string PendingPollToken { get; set; } = "";
    public string PendingEmail { get; set; } = "";
    public DateTimeOffset? PendingExpiresAt { get; set; }

    public bool CodexNotifyPromptDismissed { get; set; }
}
