using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AgentPager.Services;

public enum CodexHookConfigurationStatus
{
    Missing,
    Installed,
    Invalid
}

public static class CodexHookConfiguration
{
    private const string HookArgument = "--codex-stop-hook";

    public static CodexHookConfigurationStatus GetStatus(
        string hooksPath,
        string executablePath)
    {
        if (!File.Exists(hooksPath))
            return CodexHookConfigurationStatus.Missing;

        try
        {
            var root = ParseObject(File.ReadAllText(hooksPath));
            var handler = FindHandler(root);

            return handler?["command"]?.GetValue<string>()
                       == BuildCommand(executablePath)
                ? CodexHookConfigurationStatus.Installed
                : CodexHookConfigurationStatus.Missing;
        }
        catch (InvalidDataException)
        {
            return CodexHookConfigurationStatus.Invalid;
        }
    }

    public static void Install(
        string hooksPath,
        string executablePath)
    {
        var root = File.Exists(hooksPath)
            ? ParseObject(File.ReadAllText(hooksPath))
            : new JsonObject();

        var handler = FindHandler(root);

        if (handler is null)
        {
            var hooks = GetOrCreateObject(root, "hooks");
            var stopGroups = GetOrCreateArray(hooks, "Stop");

            handler = new JsonObject();
            stopGroups.Add(new JsonObject
            {
                ["hooks"] = new JsonArray(handler)
            });
        }

        handler["type"] = "command";
        handler["command"] = BuildCommand(executablePath);
        handler["timeout"] = 30;
        handler["statusMessage"] = "AgentPager 正在发送完成通知";

        WriteAtomically(hooksPath, root.ToJsonString(new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }

    private static JsonObject ParseObject(string json)
    {
        try
        {
            return JsonNode.Parse(json) as JsonObject
                   ?? throw new InvalidDataException("Codex hooks.json 顶层必须是 JSON 对象。");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Codex hooks.json 不是有效的 JSON。", ex);
        }
    }

    private static JsonObject? FindHandler(JsonObject root)
    {
        if (root["hooks"] is not JsonObject hooks
            || hooks["Stop"] is not JsonArray stopGroups)
        {
            return null;
        }

        foreach (var group in stopGroups.OfType<JsonObject>())
        {
            if (group["hooks"] is not JsonArray handlers)
                continue;

            foreach (var handler in handlers.OfType<JsonObject>())
            {
                var command = handler["command"]?.GetValue<string>();

                if (command?.Contains(
                        HookArgument,
                        StringComparison.Ordinal) == true)
                {
                    return handler;
                }
            }
        }

        return null;
    }

    private static JsonObject GetOrCreateObject(
        JsonObject parent,
        string name)
    {
        if (parent[name] is JsonObject existing)
            return existing;

        var created = new JsonObject();
        parent[name] = created;
        return created;
    }

    private static JsonArray GetOrCreateArray(
        JsonObject parent,
        string name)
    {
        if (parent[name] is JsonArray existing)
            return existing;

        var created = new JsonArray();
        parent[name] = created;
        return created;
    }

    private static string BuildCommand(string executablePath)
    {
        return $"\"{Path.GetFullPath(executablePath)}\" {HookArgument}";
    }

    private static void WriteAtomically(
        string hooksPath,
        string json)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(hooksPath))
                        ?? throw new InvalidOperationException("无法确定 hooks.json 目录。");
        Directory.CreateDirectory(directory);

        var tempPath = Path.Combine(
            directory,
            $".{Path.GetFileName(hooksPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            File.WriteAllText(
                tempPath,
                json,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(tempPath, hooksPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath))
                File.Delete(tempPath);
        }
    }
}
