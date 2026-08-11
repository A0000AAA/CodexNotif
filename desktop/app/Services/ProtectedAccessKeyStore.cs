using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace AgentPager.Services;

public sealed class ProtectedAccessKeyStore
{
    private static readonly byte[] Entropy =
        Encoding.UTF8.GetBytes("CodexNotif.AccessKey.v1");

    private readonly string _path;

    public ProtectedAccessKeyStore(string? path = null)
    {
        _path = Path.GetFullPath(path ?? Path.Combine(
            Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData),
            "CodexNotif",
            "access-key.dat"));
    }

    public void Save(string value)
    {
        var directory = Path.GetDirectoryName(_path)
                        ?? throw new InvalidOperationException(
                            "无法确定访问密钥存储目录。");
        Directory.CreateDirectory(directory);

        byte[] plaintext = Encoding.UTF8.GetBytes(value);
        byte[]? protectedBytes = null;
        string temporaryPath = _path + ".tmp";

        try
        {
            protectedBytes = ProtectedData.Protect(
                plaintext,
                Entropy,
                DataProtectionScope.CurrentUser);
            File.WriteAllBytes(temporaryPath, protectedBytes);
            File.Move(temporaryPath, _path, overwrite: true);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);

            if (protectedBytes is not null)
                CryptographicOperations.ZeroMemory(protectedBytes);

            try
            {
                File.Delete(temporaryPath);
            }
            catch
            {
                // A completed atomic move leaves no temporary file.
            }
        }
    }

    public string? Load()
    {
        if (!File.Exists(_path))
            return null;

        byte[]? plaintext = null;

        try
        {
            byte[] protectedBytes = File.ReadAllBytes(_path);
            plaintext = ProtectedData.Unprotect(
                protectedBytes,
                Entropy,
                DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plaintext);
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        finally
        {
            if (plaintext is not null)
                CryptographicOperations.ZeroMemory(plaintext);
        }
    }
}
