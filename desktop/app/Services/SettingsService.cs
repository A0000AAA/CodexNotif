using System.IO;
using System.Text.Json;
using AgentPager.Models;

namespace AgentPager.Services;

public sealed class SettingsService
{
    private readonly string _path;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public SettingsService(string? path = null)
    {
        if (!string.IsNullOrWhiteSpace(path))
        {
            _path = Path.GetFullPath(path);
            return;
        }

        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexNotif");

        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
    }

    public AppSettings Load()
    {
        if (!File.Exists(_path))
            return new AppSettings();

        try
        {
            var json = File.ReadAllText(_path);

            return JsonSerializer.Deserialize<AppSettings>(
                       json,
                       JsonOptions)
                   ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(_path)
                        ?? throw new InvalidOperationException(
                            "无法确定设置文件目录。");
        Directory.CreateDirectory(directory);

        var json = JsonSerializer.Serialize(
            settings,
            JsonOptions);

        File.WriteAllText(_path, json);
    }
}
