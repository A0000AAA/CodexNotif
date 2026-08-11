using System.IO;
using System.Security.Cryptography;

namespace AgentPager.Services;

public sealed class DeviceIdentityService
{
    private readonly string _path;

    public DeviceIdentityService()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AgentPager");

        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "device.id");
    }

    public string GetOrCreate()
    {
        if (File.Exists(_path))
        {
            var existing = File.ReadAllText(_path).Trim();

            if (!string.IsNullOrWhiteSpace(existing))
                return existing;
        }

        Span<byte> random = stackalloc byte[10];
        RandomNumberGenerator.Fill(random);

        var id = "D_" + Convert.ToHexString(random);
        File.WriteAllText(_path, id);

        return id;
    }
}
