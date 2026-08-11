using System.IO;
using System.Text;
using System.Text.Json;

namespace AgentPager.Services;

public enum CodexNotifyConfigurationStatus
{
    Missing,
    Installed,
    Invalid
}

public enum CodexNotifyInstallResult
{
    Installed,
    AlreadyInstalled
}

public enum CodexNotifyRestoreResult
{
    Restored,
    NothingToRestore,
    Conflict
}

public static class CodexNotifyConfiguration
{
    public const string NotifyArgument = "--codex-notify";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public static bool ShouldOfferInstall(
        CodexNotifyConfigurationStatus status,
        bool promptDismissed)
    {
        return status == CodexNotifyConfigurationStatus.Missing
               && !promptDismissed;
    }

    public static CodexNotifyConfigurationStatus GetStatus(
        string configPath,
        string executablePath)
    {
        if (!File.Exists(configPath))
            return CodexNotifyConfigurationStatus.Missing;

        try
        {
            var notify = FindTopLevelNotify(File.ReadAllText(configPath));

            if (notify is null)
                return CodexNotifyConfigurationStatus.Missing;

            return CodexNotifyCommand.TargetsExecutable(
                    notify.Command,
                    executablePath)
                ? CodexNotifyConfigurationStatus.Installed
                : CodexNotifyConfigurationStatus.Missing;
        }
        catch (InvalidDataException)
        {
            return CodexNotifyConfigurationStatus.Invalid;
        }
    }

    public static CodexNotifyInstallResult Install(
        string configPath,
        string executablePath,
        string statePath)
    {
        var fullConfigPath = Path.GetFullPath(configPath);
        var fullExecutablePath = Path.GetFullPath(executablePath);
        var fullStatePath = Path.GetFullPath(statePath);
        var originalText = File.Exists(fullConfigPath)
            ? File.ReadAllText(fullConfigPath)
            : "";
        var notify = FindTopLevelNotify(originalText);

        if (notify is not null
            && CodexNotifyCommand.TargetsExecutable(
                notify.Command,
                fullExecutablePath))
        {
            return CodexNotifyInstallResult.AlreadyInstalled;
        }

        CodexNotifyState? existingState = null;

        if (notify is not null
            && IsAnyAgentPagerCommand(notify.Command)
            && File.Exists(fullStatePath))
        {
            existingState = ReadState(fullStatePath);
        }

        var installedLine = BuildNotifyLine(fullExecutablePath);
        var edit = ReplaceOrInsertNotify(
            originalText,
            notify,
            installedLine);
        var backupPath = existingState?.BackupPath
                         ?? BuildBackupPath(fullConfigPath);
        var state = new CodexNotifyState(
            Version: 1,
            OriginalNotifyLine: existingState?.OriginalNotifyLine
                                ?? (IsAnyAgentPagerCommand(notify?.Command)
                                    ? null
                                    : notify?.Content),
            PreviousCommand: existingState?.PreviousCommand
                             ?? (IsAnyAgentPagerCommand(notify?.Command)
                                 ? []
                                 : notify?.Command ?? []),
            InstalledNotifyLine: installedLine,
            BackupPath: backupPath,
            InsertedLeadingNewline: existingState?.InsertedLeadingNewline
                                    ?? edit.InsertedLeadingNewline);

        var configDirectory = Path.GetDirectoryName(fullConfigPath)
                              ?? throw new InvalidOperationException(
                                  "无法确定 Codex 配置目录。");
        var stateDirectory = Path.GetDirectoryName(fullStatePath)
                             ?? throw new InvalidOperationException(
                                 "无法确定 CodexNotif 状态目录。");
        Directory.CreateDirectory(configDirectory);
        Directory.CreateDirectory(stateDirectory);

        var configTemp = BuildTempPath(fullConfigPath);
        var stateTemp = BuildTempPath(fullStatePath);

        try
        {
            WriteUtf8(stateTemp, JsonSerializer.Serialize(state, JsonOptions));
            WriteUtf8(configTemp, edit.Text);

            if (File.Exists(fullConfigPath)
                && !File.Exists(backupPath))
            {
                File.Copy(fullConfigPath, backupPath);
            }

            File.Move(configTemp, fullConfigPath, overwrite: true);

            try
            {
                File.Move(stateTemp, fullStatePath, overwrite: true);
            }
            catch
            {
                WriteAtomically(fullConfigPath, originalText);
                throw;
            }
        }
        finally
        {
            DeleteIfExists(configTemp);
            DeleteIfExists(stateTemp);
        }

        return CodexNotifyInstallResult.Installed;
    }

    public static CodexNotifyRestoreResult Restore(
        string configPath,
        string executablePath,
        string statePath)
    {
        _ = executablePath;

        if (!File.Exists(statePath))
            return CodexNotifyRestoreResult.NothingToRestore;

        var state = ReadState(statePath);

        if (!File.Exists(configPath))
            return CodexNotifyRestoreResult.Conflict;

        var text = File.ReadAllText(configPath);
        var notify = FindTopLevelNotify(text);

        if (notify is null
            || !string.Equals(
                notify.Content,
                state.InstalledNotifyLine,
                StringComparison.Ordinal))
        {
            return CodexNotifyRestoreResult.Conflict;
        }

        string restored;

        if (state.OriginalNotifyLine is not null)
        {
            restored = text.Remove(notify.Start, notify.ContentLength)
                .Insert(notify.Start, state.OriginalNotifyLine);
        }
        else
        {
            var removeStart = notify.Start;
            var removeLength = notify.TotalLength;

            if (state.InsertedLeadingNewline && removeStart > 0)
            {
                removeStart--;
                removeLength++;

                if (removeStart > 0
                    && text[removeStart] == '\n'
                    && text[removeStart - 1] == '\r')
                {
                    removeStart--;
                    removeLength++;
                }
            }

            restored = text.Remove(removeStart, removeLength);
        }

        WriteAtomically(configPath, restored);
        File.Delete(statePath);
        return CodexNotifyRestoreResult.Restored;
    }

    public static string[] LoadPreviousCommand(string statePath)
    {
        if (!File.Exists(statePath))
            return [];

        return [.. ReadState(statePath).PreviousCommand];
    }

    private static NotifyLine? FindTopLevelNotify(string text)
    {
        foreach (var line in EnumerateLines(text))
        {
            var trimmed = line.Content.TrimStart();

            if (trimmed.Length == 0 || trimmed.StartsWith('#'))
                continue;

            if (trimmed.StartsWith('['))
                return null;

            var equalsIndex = trimmed.IndexOf('=');

            if (equalsIndex < 0
                || !string.Equals(
                    trimmed[..equalsIndex].Trim(),
                    "notify",
                    StringComparison.Ordinal))
            {
                continue;
            }

            var value = RemoveTrailingComment(
                trimmed[(equalsIndex + 1)..]).Trim();

            try
            {
                var command = JsonSerializer.Deserialize<string[]>(value)
                              ?? throw new InvalidDataException(
                                  "Codex notify 必须是字符串数组。");

                if (command.Length == 0
                    || command.Any(string.IsNullOrWhiteSpace))
                {
                    throw new InvalidDataException(
                        "Codex notify 命令不能为空。");
                }

                return new NotifyLine(
                    line.Start,
                    line.ContentLength,
                    line.TotalLength,
                    line.Content,
                    command);
            }
            catch (JsonException ex)
            {
                throw new InvalidDataException(
                    "Codex notify 不是受支持的单行字符串数组。",
                    ex);
            }
        }

        if (ContainsUnfinishedTopLevelNotify(text))
        {
            throw new InvalidDataException(
                "Codex notify 不是受支持的单行字符串数组。");
        }

        return null;
    }

    private static bool ContainsUnfinishedTopLevelNotify(string text)
    {
        foreach (var line in EnumerateLines(text))
        {
            var trimmed = line.Content.TrimStart();

            if (trimmed.StartsWith('['))
                return false;

            if (trimmed.StartsWith("notify", StringComparison.Ordinal)
                && trimmed.Length > "notify".Length
                && char.IsWhiteSpace(trimmed["notify".Length]))
            {
                return true;
            }
        }

        return false;
    }

    private static string RemoveTrailingComment(string value)
    {
        var inString = false;
        var escaped = false;

        for (var index = 0; index < value.Length; index++)
        {
            var character = value[index];

            if (escaped)
            {
                escaped = false;
                continue;
            }

            if (inString && character == '\\')
            {
                escaped = true;
                continue;
            }

            if (character == '"')
            {
                inString = !inString;
                continue;
            }

            if (!inString && character == '#')
                return value[..index];
        }

        return value;
    }

    private static NotifyEdit ReplaceOrInsertNotify(
        string text,
        NotifyLine? notify,
        string installedLine)
    {
        if (notify is not null)
        {
            return new NotifyEdit(
                text.Remove(notify.Start, notify.ContentLength)
                    .Insert(notify.Start, installedLine),
                InsertedLeadingNewline: false);
        }

        var newline = text.Contains("\r\n", StringComparison.Ordinal)
            ? "\r\n"
            : "\n";
        var firstTable = EnumerateLines(text)
            .FirstOrDefault(line => line.Content.TrimStart().StartsWith('['));

        if (firstTable is not null)
        {
            return new NotifyEdit(
                text.Insert(firstTable.Start, installedLine + newline),
                InsertedLeadingNewline: false);
        }

        if (text.Length == 0 || text.EndsWith('\n'))
        {
            return new NotifyEdit(
                text + installedLine + newline,
                InsertedLeadingNewline: false);
        }

        return new NotifyEdit(
            text + newline + installedLine,
            InsertedLeadingNewline: true);
    }

    private static string BuildNotifyLine(string executablePath)
    {
        return "notify = " + JsonSerializer.Serialize(new[]
        {
            Path.GetFullPath(executablePath),
            NotifyArgument
        });
    }

    private static bool IsAnyAgentPagerCommand(string[]? command)
    {
        return command?.Skip(1).Contains(
            NotifyArgument,
            StringComparer.Ordinal) == true;
    }

    private static List<TextLine> EnumerateLines(string text)
    {
        var result = new List<TextLine>();
        var start = 0;

        while (start < text.Length)
        {
            var newlineIndex = text.IndexOf('\n', start);
            var totalEnd = newlineIndex >= 0
                ? newlineIndex + 1
                : text.Length;
            var contentEnd = newlineIndex >= 0
                ? newlineIndex
                : text.Length;

            if (contentEnd > start && text[contentEnd - 1] == '\r')
                contentEnd--;

            result.Add(new TextLine(
                start,
                contentEnd - start,
                totalEnd - start,
                text[start..contentEnd]));
            start = totalEnd;
        }

        return result;
    }

    private static CodexNotifyState ReadState(string statePath)
    {
        try
        {
            var state = JsonSerializer.Deserialize<CodexNotifyState>(
                File.ReadAllText(statePath),
                JsonOptions);

            return state is { Version: 1 }
                ? state
                : throw new InvalidDataException(
                    "CodexNotif Codex notify 状态版本无效。");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException(
                "CodexNotif Codex notify 状态文件无效。",
                ex);
        }
    }

    private static string BuildBackupPath(string configPath)
    {
        return configPath
               + ".codexnotif."
               + DateTime.Now.ToString("yyyyMMddHHmmssfff")
               + ".bak";
    }

    private static string BuildTempPath(string path)
    {
        var directory = Path.GetDirectoryName(path)
                        ?? throw new InvalidOperationException(
                            "无法确定临时文件目录。");
        return Path.Combine(
            directory,
            $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
    }

    private static void WriteAtomically(string path, string text)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(path))
                        ?? throw new InvalidOperationException(
                            "无法确定文件目录。");
        Directory.CreateDirectory(directory);
        var temp = BuildTempPath(Path.GetFullPath(path));

        try
        {
            WriteUtf8(temp, text);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            DeleteIfExists(temp);
        }
    }

    private static void WriteUtf8(string path, string text)
    {
        File.WriteAllText(
            path,
            text,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static void DeleteIfExists(string path)
    {
        if (File.Exists(path))
            File.Delete(path);
    }

    private sealed record TextLine(
        int Start,
        int ContentLength,
        int TotalLength,
        string Content);

    private sealed record NotifyLine(
        int Start,
        int ContentLength,
        int TotalLength,
        string Content,
        string[] Command);

    private sealed record NotifyEdit(
        string Text,
        bool InsertedLeadingNewline);

    private sealed record CodexNotifyState(
        int Version,
        string? OriginalNotifyLine,
        string[] PreviousCommand,
        string InstalledNotifyLine,
        string BackupPath,
        bool InsertedLeadingNewline);
}
