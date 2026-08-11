namespace AgentPager.Services;

public static class ServerAccessKeyResolver
{
    public const string EnvironmentVariableName = "CODEXNOTIF_ACCESS_KEY";
    public const string HeaderName = "X-CodexNotif-Access-Key";

    private const int MinimumLength = 32;
    private static readonly ServerAccessKeyPersistence Persistence = new();

    public static string? ReadOptional()
    {
        return Persistence.ReadOptional();
    }

    public static string Read()
    {
        return Validate(ReadOptional());
    }

    public static bool IsValid(string? value)
    {
        try
        {
            Validate(value);
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    public static string Validate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)
            || value.Length < MinimumLength
            || value.Any(character =>
                char.IsWhiteSpace(character)
                || char.IsControl(character)))
        {
            throw new InvalidOperationException(
                $"未配置有效的 {EnvironmentVariableName}。请在客户端的服务器设置中配置访问密钥。");
        }

        return value;
    }

    public static AccessKeySaveLocation SaveForCurrentUser(string value)
    {
        return Persistence.Save(value);
    }
}
