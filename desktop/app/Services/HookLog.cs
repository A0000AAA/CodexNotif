using System.IO;
using System.Text;

namespace AgentPager.Services;

public static class HookLog
{
    public static void Write(
        string path,
        string message,
        int maxBytes = 131072)
    {
        var fullPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(fullPath)
                        ?? throw new InvalidOperationException("无法确定 Hook 日志目录。");
        Directory.CreateDirectory(directory);

        if (File.Exists(fullPath)
            && new FileInfo(fullPath).Length >= maxBytes)
        {
            var existing = File.ReadAllBytes(fullPath);
            var keepBytes = Math.Min(existing.Length, Math.Max(1, maxBytes / 2));
            File.WriteAllBytes(fullPath, existing[^keepBytes..]);
        }

        var safeMessage = message
            .Replace('\r', ' ')
            .Replace('\n', ' ');
        var line = $"{DateTimeOffset.Now:O} {safeMessage}{Environment.NewLine}";

        File.AppendAllText(
            fullPath,
            line,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }
}
