namespace AgentPager.Models;

public sealed class BindStatusResponse
{
    public string Status { get; set; } = "";
    public string? DeviceToken { get; set; }
    public string? Email { get; set; }
}
