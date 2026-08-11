using System.IO;
using System.Text.Json;

namespace AgentPager.Services;

public static class CodexNotifyCommand
{
    private const string PreviousNotifyArgument = "--previous-notify";
    private const int MaxNestedDepth = 8;

    public static bool TargetsExecutable(
        IReadOnlyList<string> command,
        string executablePath)
    {
        return TargetsExecutable(command, executablePath, depth: 0);
    }

    public static string[] CreateSafeForwardCommand(
        IReadOnlyList<string> command)
    {
        if (command.Count == 0 || HasNotifyArgument(command))
            return [];

        var result = new List<string>(command.Count)
        {
            command[0]
        };

        for (var index = 1; index < command.Count; index++)
        {
            if (string.Equals(
                    command[index],
                    PreviousNotifyArgument,
                    StringComparison.Ordinal)
                && index + 1 < command.Count
                && TryParseCommand(command[index + 1], out var nestedCommand)
                && ContainsNotifyCommand(nestedCommand, depth: 0))
            {
                index++;
                continue;
            }

            result.Add(command[index]);
        }

        return [.. result];
    }

    private static bool TargetsExecutable(
        IReadOnlyList<string> command,
        string executablePath,
        int depth)
    {
        if (IsDirectTarget(command, executablePath))
            return true;

        if (depth >= MaxNestedDepth)
            return false;

        for (var index = 1; index + 1 < command.Count; index++)
        {
            if (!string.Equals(
                    command[index],
                    PreviousNotifyArgument,
                    StringComparison.Ordinal)
                || !TryParseCommand(command[index + 1], out var nestedCommand))
            {
                continue;
            }

            if (TargetsExecutable(
                    nestedCommand,
                    executablePath,
                    depth + 1))
            {
                return true;
            }

            index++;
        }

        return false;
    }

    private static bool ContainsNotifyCommand(
        IReadOnlyList<string> command,
        int depth)
    {
        if (HasNotifyArgument(command))
            return true;

        if (depth >= MaxNestedDepth)
            return false;

        for (var index = 1; index + 1 < command.Count; index++)
        {
            if (!string.Equals(
                    command[index],
                    PreviousNotifyArgument,
                    StringComparison.Ordinal)
                || !TryParseCommand(command[index + 1], out var nestedCommand))
            {
                continue;
            }

            if (ContainsNotifyCommand(nestedCommand, depth + 1))
                return true;

            index++;
        }

        return false;
    }

    private static bool IsDirectTarget(
        IReadOnlyList<string> command,
        string executablePath)
    {
        if (command.Count < 2 || !HasNotifyArgument(command))
            return false;

        try
        {
            return string.Equals(
                Path.GetFullPath(command[0]),
                Path.GetFullPath(executablePath),
                StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static bool HasNotifyArgument(IReadOnlyList<string> command)
    {
        for (var index = 1; index < command.Count; index++)
        {
            if (string.Equals(
                    command[index],
                    CodexNotifyConfiguration.NotifyArgument,
                    StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryParseCommand(
        string json,
        out string[] command)
    {
        try
        {
            command = JsonSerializer.Deserialize<string[]>(json) ?? [];
            return command.Length > 0
                   && command.All(value => !string.IsNullOrWhiteSpace(value));
        }
        catch (JsonException)
        {
            command = [];
            return false;
        }
    }
}
