namespace AgentPager.Models;

public sealed class AuthCheckResponse
{
    public bool AccessKeyAuthenticated { get; set; }
    public bool DeviceAuthenticated { get; set; }
}
