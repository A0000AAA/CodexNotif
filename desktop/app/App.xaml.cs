using System.IO;
using System.Windows;
using AgentPager.Services;

namespace AgentPager;

public partial class App : Application
{
    private const string StopHookArgument = "--codex-stop-hook";
    private const string NotifyArgument = "--codex-notify";
    private const string InstallNotifyArgument = "--install-codex-notify";
    private const string RestoreNotifyArgument = "--restore-codex-notify";

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (e.Args is [InstallNotifyArgument, var configPath, var statePath])
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(RunNotifyConfigurationCommand(
                install: true,
                configPath,
                statePath));
            return;
        }

        if (e.Args is [RestoreNotifyArgument, var restoreConfigPath, var restoreStatePath])
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            Shutdown(RunNotifyConfigurationCommand(
                install: false,
                restoreConfigPath,
                restoreStatePath));
            return;
        }

        if (e.Args is [NotifyArgument, var payload])
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            await RunNotifyAsync(payload);
            Shutdown(0);
            return;
        }

        if (e.Args.Contains(StopHookArgument, StringComparer.Ordinal))
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            if (IsNotifyInstalled())
                await WriteStopContinueAsync();
            else
                await RunStopHookAsync();

            Shutdown(0);
            return;
        }

        MainWindow = new MainWindow();
        MainWindow.Show();
    }

    private static int RunNotifyConfigurationCommand(
        bool install,
        string configPath,
        string statePath)
    {
        try
        {
            var executablePath = Environment.ProcessPath
                                 ?? throw new InvalidOperationException(
                                     "无法确定 CodexNotif.exe 路径。");

            if (install)
            {
                CodexNotifyConfiguration.Install(
                    configPath,
                    executablePath,
                    statePath);
                return 0;
            }

            var result = CodexNotifyConfiguration.Restore(
                configPath,
                executablePath,
                statePath);

            return result == CodexNotifyRestoreResult.Conflict
                ? 2
                : 0;
        }
        catch
        {
            return 1;
        }
    }

    private static async Task RunNotifyAsync(string payload)
    {
        var appData = GetAppDataDirectory();
        var logPath = Path.Combine(appData, "hook.log");
        var statePath = Path.Combine(
            appData,
            "codex-notify-state.json");
        string[] previousCommand;

        try
        {
            previousCommand =
                CodexNotifyConfiguration.LoadPreviousCommand(statePath);
        }
        catch (Exception ex)
        {
            previousCommand = [];
            TryWriteLog(
                logPath,
                $"Codex notify 状态读取失败：{ex.GetType().Name}");
        }

        try
        {
            var settings = new SettingsService().Load();
            var server = ServerAddressResolver.Resolve(
                settings.ServerBaseUrl);
            using var relay = new RelayApiClient(server.BaseUrl);
            using var timeout = new CancellationTokenSource(
                TimeSpan.FromSeconds(25));

            await CodexNotifyRunner.RunAsync(
                payload,
                new DeviceIdentityService().GetOrCreate(),
                settings,
                (agentEvent, token, cancellationToken) =>
                    relay.SendEventAsync(
                        agentEvent,
                        token,
                        cancellationToken),
                (json, cancellationToken) =>
                    CodexNotifyForwarder.RunAsync(
                        previousCommand,
                        json,
                        message => TryWriteLog(logPath, message),
                        cancellationToken),
                message => TryWriteLog(logPath, message),
                timeout.Token);
        }
        catch (Exception ex)
        {
            TryWriteLog(
                logPath,
                $"Codex notify 启动失败：{ex.GetType().Name}");
        }
    }

    private static async Task RunStopHookAsync()
    {
        var appData = GetAppDataDirectory();
        var logPath = Path.Combine(appData, "hook.log");

        try
        {
            var settings = new SettingsService().Load();
            var server = ServerAddressResolver.Resolve(
                settings.ServerBaseUrl);
            using var relay = new RelayApiClient(server.BaseUrl);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));

            await CodexStopHookRunner.RunAsync(
                Console.In,
                Console.Out,
                new DeviceIdentityService().GetOrCreate(),
                settings,
                (agentEvent, token, cancellationToken) =>
                    relay.SendEventAsync(agentEvent, token, cancellationToken),
                message => HookLog.Write(logPath, message),
                timeout.Token);
        }
        catch (Exception ex)
        {
            await Console.Error.WriteLineAsync(
                $"CodexNotif Stop Hook startup error: {ex.GetType().Name}");

            try
            {
                HookLog.Write(
                    logPath,
                    $"Codex Stop Hook 启动失败：{ex.GetType().Name}");
            }
            catch
            {
                // Hook must still release Codex when local diagnostics fail.
            }

            await Console.Out.WriteAsync("{\"continue\":true}");
            await Console.Out.FlushAsync();
        }
    }

    private static bool IsNotifyInstalled()
    {
        var executablePath = Environment.ProcessPath;

        if (string.IsNullOrWhiteSpace(executablePath))
            return false;

        return CodexNotifyConfiguration.GetStatus(
                   Path.Combine(
                       Environment.GetFolderPath(
                           Environment.SpecialFolder.UserProfile),
                       ".codex",
                       "config.toml"),
                   executablePath)
               == CodexNotifyConfigurationStatus.Installed;
    }

    private static async Task WriteStopContinueAsync()
    {
        await Console.Out.WriteAsync("{\"continue\":true}");
        await Console.Out.FlushAsync();
    }

    private static string GetAppDataDirectory()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData),
            "CodexNotif");
        Directory.CreateDirectory(directory);
        return directory;
    }

    private static void TryWriteLog(
        string logPath,
        string message)
    {
        try
        {
            HookLog.Write(logPath, message);
        }
        catch
        {
            // Headless notification paths must never fail because diagnostics did.
        }
    }
}
