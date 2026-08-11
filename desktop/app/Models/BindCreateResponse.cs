namespace AgentPager.Models;

public sealed class BindCreateResponse
{
    public string BindId { get; set; } = "";
    public string PollToken { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
}
