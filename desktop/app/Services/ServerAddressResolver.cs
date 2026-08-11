namespace AgentPager.Services;

public enum ServerAddressSource
{
    ClientSettings,
    EnvironmentVariable,
    BuiltInDefault
}

public sealed record ServerAddressResolution(
    string BaseUrl,
    ServerAddressSource Source);

public static class ServerAddressResolver
{
    public const string DefaultBaseUrl = "http://localhost:27843";

    public static ServerAddressResolution Resolve(string? savedBaseUrl)
    {
        return Resolve(
            savedBaseUrl,
            Environment.GetEnvironmentVariable(
                "CODEXNOTIF_SERVER_URL"));
    }

    public static ServerAddressResolution Resolve(
        string? savedBaseUrl,
        string? environmentBaseUrl)
    {
        if (!string.IsNullOrWhiteSpace(savedBaseUrl))
        {
            return new ServerAddressResolution(
                Normalize(savedBaseUrl),
                ServerAddressSource.ClientSettings);
        }

        if (!string.IsNullOrWhiteSpace(environmentBaseUrl))
        {
            return new ServerAddressResolution(
                Normalize(environmentBaseUrl),
                ServerAddressSource.EnvironmentVariable);
        }

        return new ServerAddressResolution(
            DefaultBaseUrl,
            ServerAddressSource.BuiltInDefault);
    }

    public static string Normalize(string value)
    {
        var trimmed = value.Trim();

        if (!Uri.TryCreate(
                trimmed,
                UriKind.Absolute,
                out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp
                && uri.Scheme != Uri.UriSchemeHttps)
            || string.IsNullOrWhiteSpace(uri.Host)
            || !string.IsNullOrEmpty(uri.UserInfo)
            || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment))
        {
            throw new ArgumentException(
                "请输入不含账号、查询参数和片段的完整 HTTP(S) 服务器地址。",
                nameof(value));
        }

        return uri.GetLeftPart(UriPartial.Path).TrimEnd('/');
    }
}
