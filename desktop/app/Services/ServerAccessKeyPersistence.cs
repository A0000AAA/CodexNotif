using System.Security;

namespace AgentPager.Services;

public enum AccessKeySaveLocation
{
    UserEnvironment,
    ProtectedLocalStorage
}

public sealed class ServerAccessKeyPersistence
{
    private readonly ProtectedAccessKeyStore _protectedStore;
    private readonly Func<EnvironmentVariableTarget, string?> _readEnvironment;
    private readonly Action<EnvironmentVariableTarget, string?> _writeEnvironment;

    public ServerAccessKeyPersistence(
        ProtectedAccessKeyStore? protectedStore = null,
        Func<EnvironmentVariableTarget, string?>? readEnvironment = null,
        Action<EnvironmentVariableTarget, string?>? writeEnvironment = null)
    {
        _protectedStore = protectedStore ?? new ProtectedAccessKeyStore();
        _readEnvironment = readEnvironment ?? (target =>
            Environment.GetEnvironmentVariable(
                ServerAccessKeyResolver.EnvironmentVariableName,
                target));
        _writeEnvironment = writeEnvironment ?? ((target, value) =>
            Environment.SetEnvironmentVariable(
                ServerAccessKeyResolver.EnvironmentVariableName,
                value,
                target));
    }

    public string? ReadOptional()
    {
        string? protectedValue = _protectedStore.Load();

        if (ServerAccessKeyResolver.IsValid(protectedValue))
            return protectedValue;

        return _readEnvironment(EnvironmentVariableTarget.Process)
               ?? _readEnvironment(EnvironmentVariableTarget.User);
    }

    public AccessKeySaveLocation Save(string value)
    {
        string key = ServerAccessKeyResolver.Validate(value);
        _protectedStore.Save(key);

        try
        {
            _writeEnvironment(EnvironmentVariableTarget.User, key);
            TryWriteProcess(key);
            return AccessKeySaveLocation.UserEnvironment;
        }
        catch (SecurityException)
        {
            TryWriteProcess(key);
            return AccessKeySaveLocation.ProtectedLocalStorage;
        }
        catch (UnauthorizedAccessException)
        {
            TryWriteProcess(key);
            return AccessKeySaveLocation.ProtectedLocalStorage;
        }
    }

    private void TryWriteProcess(string key)
    {
        try
        {
            _writeEnvironment(EnvironmentVariableTarget.Process, key);
        }
        catch (SecurityException)
        {
            // Protected storage remains authoritative for this user.
        }
        catch (UnauthorizedAccessException)
        {
            // Protected storage remains authoritative for this user.
        }
    }
}
