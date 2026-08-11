using System.Text.Json;
using System.Diagnostics;
using System.Net;
using System.Security;
using System.Text;
using AgentPager.Models;
using AgentPager.Services;

if (args is ["--capture-notify", var capturePath, var capturedPayload])
{
    File.WriteAllText(capturePath, capturedPayload);
    return 0;
}

if (args is ["--capture-arguments", var argumentsPath, .. var capturedArguments])
{
    File.WriteAllText(
        argumentsPath,
        JsonSerializer.Serialize(capturedArguments));
    return 0;
}

var failures = new List<string>();

Run("saved server URL wins and normalizes", () =>
{
    var resolved = ServerAddressResolver.Resolve(
        " https://notify.example.com/base/ ",
        "https://notify.example.com/environment");

    Assert(
        resolved.BaseUrl == "https://notify.example.com/base",
        "saved URL must win and normalize");
    Assert(
        resolved.Source == ServerAddressSource.ClientSettings,
        "saved URL source must be reported");
});

Run("server URL falls back to environment then default", () =>
{
    var environment = ServerAddressResolver.Resolve(
        null,
        "https://notify.example.com/environment/");
    var builtIn = ServerAddressResolver.Resolve("", "");

    Assert(
        environment == new ServerAddressResolution(
            "https://notify.example.com/environment",
            ServerAddressSource.EnvironmentVariable),
        "empty saved URL must use the environment");
    Assert(
        builtIn == new ServerAddressResolution(
            "http://localhost:27843",
            ServerAddressSource.BuiltInDefault),
        "empty saved and environment URLs must use the default");
});

Run("invalid server URLs are rejected", () =>
{
    foreach (var invalid in new[]
             {
                 "relative/path",
                 "ftp://notify.example.com",
                 "http://notify.example.com",
                 "http://localhost@localhost",
                 "https://notify.example.com?token=value",
                 "https://notify.example.com/#fragment"
             })
    {
        AssertThrows<ArgumentException>(() =>
            ServerAddressResolver.Normalize(invalid));
    }
});

Run("access key resolver rejects missing and unsafe values", () =>
{
    foreach (var invalid in new string?[]
             {
                 null,
                 "",
                 "short",
                 " " + new string('x', 32),
                 new string('x', 32) + "\r\n"
             })
    {
        AssertThrows<InvalidOperationException>(() =>
            ServerAccessKeyResolver.Validate(invalid));
    }
});

Run("access key persistence uses process before user without protected value", () =>
{
    using var temp = new TempDirectory();
    var expected = new string('p', 32);
    var persistence = new ServerAccessKeyPersistence(
        new ProtectedAccessKeyStore(
            Path.Combine(temp.Path, "access-key.dat")),
        target => target == EnvironmentVariableTarget.Process
            ? expected
            : new string('u', 32),
        (_, _) => { });

    Assert(
        persistence.ReadOptional() == expected,
        "process access key must win when protected storage is empty");
});

Run("protected access key wins over inherited environment values", () =>
{
    using var temp = new TempDirectory();
    var store = new ProtectedAccessKeyStore(
        Path.Combine(temp.Path, "access-key.dat"));
    var expected = new string('d', 32);
    store.Save(expected);
    var persistence = new ServerAccessKeyPersistence(
        store,
        _ => new string('e', 32),
        (_, _) => { });

    Assert(
        persistence.ReadOptional() == expected,
        "protected access key must override inherited environment values");
});

Run("access key save rejects invalid values before persistence", () =>
{
    AssertThrows<InvalidOperationException>(() =>
        ServerAccessKeyResolver.SaveForCurrentUser("short"));
});

Run("protected access key store encrypts and restores the value", () =>
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "access-key.dat");
    var store = new ProtectedAccessKeyStore(path);
    var key = new string('s', 32);

    store.Save(key);

    Assert(store.Load() == key, "DPAPI store must restore the key");
    Assert(
        File.ReadAllBytes(path).AsSpan().IndexOf(
            Encoding.UTF8.GetBytes(key)) < 0,
        "DPAPI file must not contain plaintext key bytes");
});

Run("access key persistence falls back when user environment is denied", () =>
{
    using var temp = new TempDirectory();
    var store = new ProtectedAccessKeyStore(
        Path.Combine(temp.Path, "access-key.dat"));
    string? processValue = null;
    var persistence = new ServerAccessKeyPersistence(
        store,
        target => target == EnvironmentVariableTarget.Process
            ? processValue
            : null,
        (target, value) =>
        {
            if (target == EnvironmentVariableTarget.User)
                throw new SecurityException("simulated policy denial");

            processValue = value;
        });
    var key = new string('f', 32);

    var location = persistence.Save(key);

    Assert(
        location == AccessKeySaveLocation.ProtectedLocalStorage,
        "denied user environment must use protected local storage");
    Assert(
        persistence.ReadOptional() == key,
        "protected fallback must be readable by later client paths");
    Assert(
        processValue == key,
        "current process must use the newly saved key immediately");
});

await RunAsync("relay rejects a missing access key before network access", async () =>
{
    var handler = new CaptureHttpHandler();
    using var relay = new RelayApiClient(
        "https://notify.example.com",
        null,
        handler);

    try
    {
        await relay.HealthAsync();
        throw new Exception("missing access key was accepted");
    }
    catch (InvalidOperationException)
    {
        // Expected: configuration errors must fail before HTTP is attempted.
    }

    Assert(handler.Requests.Count == 0, "missing key must not reach HTTP");
});

await RunAsync("relay sends access key on every API request", async () =>
{
    var handler = new CaptureHttpHandler();
    var accessKey = new string('x', 32);
    using var relay = new RelayApiClient(
        "https://notify.example.com",
        accessKey,
        handler);

    Assert(await relay.HealthAsync(), "health response must be parsed");
    await relay.CreateBindingAsync(
        "D_TEST",
        "user@example.test",
        "device-token");
    await relay.GetBindingStatusAsync("B_TEST", "poll-token");
    await relay.SendEventAsync(
        new AgentEvent(
            "D_TEST",
            "codex",
            "agent-turn-complete",
            DateTimeOffset.UtcNow),
        "device-token");
    var auth = await relay.CheckAuthenticationAsync(
        "D_TEST",
        "device-token");

    Assert(auth.AccessKeyAuthenticated, "access key status must be parsed");
    Assert(auth.DeviceAuthenticated, "device token status must be parsed");
    Assert(handler.Requests.Count == 5, "all five API calls must be captured");
    Assert(
        handler.Requests.All(request => request.AccessKey == accessKey),
        "every API request must carry the deployment access key");
    Assert(
        handler.Requests
            .Where(request => request.Path is "/api/v1/events" or "/api/v1/auth/check")
            .All(request => request.AuthorizationScheme == "Bearer"
                            && request.AuthorizationParameter == "device-token"),
        "event and authentication checks must carry the device token");
});

Run("relay client keeps the explicit normalized server URL", () =>
{
    using var relay = new RelayApiClient(
        "https://notify.example.com/base/",
        new string('x', 32));

    Assert(
        relay.ServerBaseUrl == "https://notify.example.com/base",
        "relay client must use its explicit normalized URL");
});

Run("server URL persists without changing binding data", () =>
{
    using var temp = new TempDirectory();
    var service = new SettingsService(
        Path.Combine(temp.Path, "settings.json"));
    var settings = BoundSettings();
    settings.PendingBindId = "B_TEST";
    settings.PendingEmail = "pending@example.test";
    settings.ServerBaseUrl = "https://notify.example.com";

    service.Save(settings);
    var loaded = service.Load();

    Assert(
        loaded.ServerBaseUrl == settings.ServerBaseUrl,
        "server URL must persist");
    Assert(
        loaded.DeviceToken == settings.DeviceToken
        && loaded.BoundEmail == settings.BoundEmail
        && loaded.PendingBindId == settings.PendingBindId
        && loaded.PendingEmail == settings.PendingEmail,
        "binding data must remain intact");
});

Run("legacy settings without server URL still load", () =>
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "settings.json");
    File.WriteAllText(
        path,
        """
        {
          "DeviceToken": "token",
          "BoundEmail": "bound@example.test"
        }
        """);

    var loaded = new SettingsService(path).Load();

    Assert(
        loaded.ServerBaseUrl == "",
        "legacy settings must default to an empty saved server URL");
    Assert(
        loaded.DeviceToken == "token"
        && loaded.BoundEmail == "bound@example.test",
        "legacy binding data must remain readable");
});

Run("installs once and preserves existing hooks", () =>
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "hooks.json");
    const string executable = @"C:\Agent Pager\AgentPager.exe";

    File.WriteAllText(
        path,
        """
        {
          "description": "keep me",
          "hooks": {
            "SessionEnd": [
              {
                "hooks": [
                  { "type": "command", "command": "existing.exe" }
                ]
              }
            ]
          }
        }
        """);

    Assert(
        CodexHookConfiguration.GetStatus(path, executable)
            == CodexHookConfigurationStatus.Missing,
        "a file without AgentPager must be Missing");

    CodexHookConfiguration.Install(path, executable);
    var installed = File.ReadAllText(path);

    Assert(installed.Contains("keep me"), "top-level data must remain");
    Assert(installed.Contains("existing.exe"), "existing hook must remain");
    Assert(Count(installed, "--codex-stop-hook") == 1, "hook must be added once");
    Assert(
        CodexHookConfiguration.GetStatus(path, executable)
            == CodexHookConfigurationStatus.Installed,
        "the exact quoted command must be detected");

    CodexHookConfiguration.Install(path, executable);
    Assert(
        Count(File.ReadAllText(path), "--codex-stop-hook") == 1,
        "installation must be idempotent");
});

Run("invalid JSON is not overwritten", () =>
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "hooks.json");
    const string original = "{ invalid";
    File.WriteAllText(path, original);

    Assert(
        CodexHookConfiguration.GetStatus(path, "AgentPager.exe")
            == CodexHookConfigurationStatus.Invalid,
        "invalid JSON must report Invalid");

    try
    {
        CodexHookConfiguration.Install(path, "AgentPager.exe");
        throw new Exception("Install should reject invalid JSON");
    }
    catch (InvalidDataException)
    {
        // Expected.
    }

    Assert(File.ReadAllText(path) == original, "invalid file must remain unchanged");
});

Run("notify install preserves config and previous command", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "codex-notify-state.json");
    const string executable = @"C:\Agent Pager\AgentPager.exe";

    File.WriteAllText(
        config,
        "model = \"gpt-5\"\r\n"
        + "notify = [\"old-notifier.exe\", \"turn-ended\"] # keep forwarding\r\n"
        + "[features]\r\nhooks = true\r\n");

    var result = CodexNotifyConfiguration.Install(
        config,
        executable,
        state);
    var installed = File.ReadAllText(config);

    Assert(
        result == CodexNotifyInstallResult.Installed,
        "install must succeed");
    Assert(
        installed.Contains("model = \"gpt-5\""),
        "model must remain");
    Assert(
        installed.Contains("[features]"),
        "tables must remain");
    Assert(
        Count(installed, "--codex-notify") == 1,
        "notify must be installed once");
    Assert(
        CodexNotifyConfiguration.LoadPreviousCommand(state)
            .SequenceEqual(new[] { "old-notifier.exe", "turn-ended" }),
        "the full previous command must be preserved");
});

Run("wrapped CodexNotif command is already installed", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "codex-notify-state.json");
    const string executable = @"C:\Apps\CodexNotif.exe";
    var nestedNotify = JsonSerializer.Serialize(new[]
    {
        executable,
        CodexNotifyConfiguration.NotifyArgument
    });
    var wrapper = new[]
    {
        "codex-computer-use.exe",
        "turn-ended",
        "--previous-notify",
        nestedNotify
    };
    var original = "notify = " + JsonSerializer.Serialize(wrapper) + "\n";
    File.WriteAllText(config, original);

    Assert(
        CodexNotifyConfiguration.GetStatus(config, executable)
            == CodexNotifyConfigurationStatus.Installed,
        "a wrapper targeting this CodexNotif executable must be Installed");
    Assert(
        CodexNotifyConfiguration.Install(config, executable, state)
            == CodexNotifyInstallResult.AlreadyInstalled,
        "install must not replace a wrapper that already targets CodexNotif");
    Assert(
        File.ReadAllText(config) == original,
        "already-installed wrapper config must remain unchanged");
    Assert(
        !File.Exists(state),
        "already-installed wrapper must not create forwarding state");
});

Run("notify install is idempotent and restore is surgical", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "state.json");
    const string executable = @"C:\AgentPager.exe";
    const string original =
        "notify = [\"old.exe\", \"arg\"]\r\n"
        + "[ui]\r\ntheme = \"dark\"\r\n";
    File.WriteAllText(config, original);

    CodexNotifyConfiguration.Install(config, executable, state);
    CodexNotifyConfiguration.Install(config, executable, state);

    Assert(
        Count(File.ReadAllText(config), "--codex-notify") == 1,
        "repeat install must not nest AgentPager");
    Assert(
        CodexNotifyConfiguration.Restore(config, executable, state)
            == CodexNotifyRestoreResult.Restored,
        "restore must succeed");
    Assert(
        File.ReadAllText(config) == original,
        "restore must reproduce original config");
});

Run("unsupported notify syntax is never overwritten", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "state.json");
    const string original = "notify = [\n  'custom.exe'\n]\n";
    File.WriteAllText(config, original);

    Assert(
        CodexNotifyConfiguration.GetStatus(config, "AgentPager.exe")
            == CodexNotifyConfigurationStatus.Invalid,
        "unsupported multiline syntax must report Invalid");
    AssertThrows<InvalidDataException>(() =>
        CodexNotifyConfiguration.Install(
            config,
            "AgentPager.exe",
            state));
    Assert(
        File.ReadAllText(config) == original,
        "invalid input must remain byte-for-byte unchanged");
    Assert(
        !File.Exists(state),
        "invalid input must not create state");
});

Run("missing notify is inserted before the first table", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "state.json");
    File.WriteAllText(
        config,
        "model = \"gpt-5\"\n[features]\nhooks = true\n");

    CodexNotifyConfiguration.Install(
        config,
        @"C:\AgentPager.exe",
        state);
    var text = File.ReadAllText(config);

    Assert(
        text.IndexOf("notify =", StringComparison.Ordinal)
        < text.IndexOf("[features]", StringComparison.Ordinal),
        "top-level notify must be inserted before tables");
    Assert(
        CodexNotifyConfiguration.LoadPreviousCommand(state).Length == 0,
        "missing notify has no previous receiver");
});

Run("restore refuses a user-replaced notify", () =>
{
    using var temp = new TempDirectory();
    var config = Path.Combine(temp.Path, "config.toml");
    var state = Path.Combine(temp.Path, "state.json");
    File.WriteAllText(config, "notify = [\"old.exe\"]\n");

    CodexNotifyConfiguration.Install(
        config,
        @"C:\AgentPager.exe",
        state);
    File.WriteAllText(config, "notify = [\"user-new.exe\"]\n");

    Assert(
        CodexNotifyConfiguration.Restore(
            config,
            @"C:\AgentPager.exe",
            state)
        == CodexNotifyRestoreResult.Conflict,
        "restore must not overwrite a later user choice");
    Assert(
        File.ReadAllText(config).Contains("user-new.exe"),
        "the user's replacement must remain");
});

Run("automatic install prompt is offered only once for missing config", () =>
{
    Assert(
        CodexNotifyConfiguration.ShouldOfferInstall(
            CodexNotifyConfigurationStatus.Missing,
            promptDismissed: false),
        "missing config must offer one authorization prompt");
    Assert(
        !CodexNotifyConfiguration.ShouldOfferInstall(
            CodexNotifyConfigurationStatus.Missing,
            promptDismissed: true),
        "dismissed prompt must not repeat");
    Assert(
        !CodexNotifyConfiguration.ShouldOfferInstall(
            CodexNotifyConfigurationStatus.Installed,
            promptDismissed: false),
        "installed config must never prompt");
    Assert(
        !CodexNotifyConfiguration.ShouldOfferInstall(
            CodexNotifyConfigurationStatus.Invalid,
            promptDismissed: false),
        "invalid config must show status without automatic modification");
});

await RunAsync("Stop sends one sanitized completion event", async () =>
{
    var sent = new List<AgentEvent>();
    var logs = new List<string>();
    using var output = new StringWriter();

    await CodexStopHookRunner.RunAsync(
        new StringReader(
            """
            {
              "hook_event_name": "Stop",
              "turn_id": "turn-1",
              "last_assistant_message": "SECRET_MESSAGE_BODY"
            }
            """),
        output,
        "D_TEST",
        new AppSettings
        {
            DeviceToken = "token",
            BoundEmail = "bound@example.test"
        },
        (agentEvent, token, _) =>
        {
            Assert(token == "token", "bound token must be used");
            sent.Add(agentEvent);
            return Task.CompletedTask;
        },
        logs.Add,
        CancellationToken.None);

    Assert(sent.Count == 1, "Stop must send exactly once");
    Assert(sent[0].Source == "codex", "source must be codex");
    Assert(sent[0].EventType == "agent.completed", "event type must be agent.completed");
    Assert(sent[0].DeviceId == "D_TEST", "device id must be preserved");
    Assert(!string.Join('\n', logs).Contains("SECRET_MESSAGE_BODY"), "message body must not be logged");
    AssertContinueOutput(output.ToString());
});

await RunAsync("non-Stop input does not send", async () =>
{
    var sends = 0;
    using var output = new StringWriter();

    await CodexStopHookRunner.RunAsync(
        new StringReader("""{"hook_event_name":"SubagentStop","turn_id":"turn-2"}"""),
        output,
        "D_TEST",
        BoundSettings(),
        (_, _, _) =>
        {
            sends++;
            return Task.CompletedTask;
        },
        _ => { },
        CancellationToken.None);

    Assert(sends == 0, "SubagentStop must not send");
    AssertContinueOutput(output.ToString());
});

await RunAsync("invalid input does not send or block Codex", async () =>
{
    var sends = 0;
    var logs = new List<string>();
    using var output = new StringWriter();

    await CodexStopHookRunner.RunAsync(
        new StringReader("not json SECRET_MESSAGE_BODY"),
        output,
        "D_TEST",
        BoundSettings(),
        (_, _, _) =>
        {
            sends++;
            return Task.CompletedTask;
        },
        logs.Add,
        CancellationToken.None);

    Assert(sends == 0, "invalid JSON must not send");
    Assert(!string.Join('\n', logs).Contains("SECRET_MESSAGE_BODY"), "raw invalid input must not be logged");
    AssertContinueOutput(output.ToString());
});

await RunAsync("unbound device does not send", async () =>
{
    var sends = 0;
    using var output = new StringWriter();

    await CodexStopHookRunner.RunAsync(
        new StringReader("""{"hook_event_name":"Stop","turn_id":"turn-3"}"""),
        output,
        "D_TEST",
        new AppSettings(),
        (_, _, _) =>
        {
            sends++;
            return Task.CompletedTask;
        },
        _ => { },
        CancellationToken.None);

    Assert(sends == 0, "unbound devices must not send");
    AssertContinueOutput(output.ToString());
});

await RunAsync("logging failure does not break Hook output", async () =>
{
    using var output = new StringWriter();

    await CodexStopHookRunner.RunAsync(
        new StringReader("""{"hook_event_name":"Unknown"}"""),
        output,
        "D_TEST",
        BoundSettings(),
        (_, _, _) => Task.CompletedTask,
        _ => throw new UnauthorizedAccessException("log denied"),
        CancellationToken.None);

    AssertContinueOutput(output.ToString());
});

await RunAsync("agent-turn-complete sends once and forwards exact JSON", async () =>
{
    const string payload =
        "{\"type\":\"agent-turn-complete\",\"turn-id\":\"T1\","
        + "\"last-assistant-message\":\"SECRET_MESSAGE_BODY\"}";
    var sent = new List<AgentEvent>();
    string? forwarded = null;
    var logs = new List<string>();

    await CodexNotifyRunner.RunAsync(
        payload,
        "D_TEST",
        BoundSettings(),
        (agentEvent, token, _) =>
        {
            Assert(token == "token", "device token must be used");
            sent.Add(agentEvent);
            return Task.CompletedTask;
        },
        (json, _) =>
        {
            forwarded = json;
            return Task.CompletedTask;
        },
        logs.Add,
        CancellationToken.None);

    Assert(sent.Count == 1, "completion must send once");
    Assert(
        sent[0].Source == "codex"
        && sent[0].EventType == "agent.completed",
        "only the sanitized event envelope may be sent");
    Assert(
        forwarded == payload,
        "old notifier must receive byte-identical JSON");
    Assert(
        !string.Join('\n', logs).Contains("SECRET_MESSAGE_BODY"),
        "message body must never be logged");
});

await RunAsync("unbound completion still forwards without mail", async () =>
{
    var sends = 0;
    var forwards = 0;

    await CodexNotifyRunner.RunAsync(
        "{\"type\":\"agent-turn-complete\"}",
        "D_TEST",
        new AppSettings(),
        (_, _, _) =>
        {
            sends++;
            return Task.CompletedTask;
        },
        (_, _) =>
        {
            forwards++;
            return Task.CompletedTask;
        },
        _ => { },
        CancellationToken.None);

    Assert(
        sends == 0 && forwards == 1,
        "unbound devices must preserve the previous notifier");
});

await RunAsync("mail and forward failures are isolated", async () =>
{
    var mailAttempts = 0;
    var forwardAttempts = 0;

    await CodexNotifyRunner.RunAsync(
        "{\"type\":\"agent-turn-complete\"}",
        "D_TEST",
        BoundSettings(),
        (_, _, _) =>
        {
            mailAttempts++;
            throw new IOException("mail failed");
        },
        (_, _) =>
        {
            forwardAttempts++;
            throw new IOException("forward failed");
        },
        _ => throw new UnauthorizedAccessException("log denied"),
        CancellationToken.None);

    Assert(
        mailAttempts == 1 && forwardAttempts == 1,
        "both independent paths must be attempted exactly once");
});

await RunAsync("invalid or non-target notify payload is ignored", async () =>
{
    var calls = 0;

    foreach (var payload in new[]
             {
                 "not-json SECRET_MESSAGE_BODY",
                 "{\"type\":\"other\",\"last-assistant-message\":\"SECRET_MESSAGE_BODY\"}"
             })
    {
        await CodexNotifyRunner.RunAsync(
            payload,
            "D_TEST",
            BoundSettings(),
            (_, _, _) =>
            {
                calls++;
                return Task.CompletedTask;
            },
            (_, _) =>
            {
                calls++;
                return Task.CompletedTask;
            },
            _ => { },
            CancellationToken.None);
    }

    Assert(calls == 0, "non-completion input must call neither destination");
});

await RunAsync("previous notifier receives exact payload through process arguments", async () =>
{
    using var temp = new TempDirectory();
    var capturePath = Path.Combine(temp.Path, "captured.json");
    const string payload =
        "{\"type\":\"agent-turn-complete\",\"text\":\"空 格 & symbols\"}";

    await CodexNotifyForwarder.RunAsync(
        new[]
        {
            Environment.ProcessPath
            ?? throw new Exception("self-test executable path is missing"),
            "--capture-notify",
            capturePath
        },
        payload,
        _ => { },
        CancellationToken.None);

    Assert(File.Exists(capturePath), "previous notifier must be launched");
    Assert(
        File.ReadAllText(capturePath) == payload,
        "payload must cross the process boundary unchanged");
});

await RunAsync("recursive previous-notify is removed before forwarding", async () =>
{
    using var temp = new TempDirectory();
    var capturePath = Path.Combine(temp.Path, "arguments.json");
    var executable = Environment.ProcessPath
                     ?? throw new Exception("self-test executable path is missing");
    var nestedNotify = JsonSerializer.Serialize(new[]
    {
        executable,
        CodexNotifyConfiguration.NotifyArgument
    });
    const string payload = "{\"type\":\"agent-turn-complete\"}";

    await CodexNotifyForwarder.RunAsync(
        new[]
        {
            executable,
            "--capture-arguments",
            capturePath,
            "--previous-notify",
            nestedNotify
        },
        payload,
        _ => { },
        CancellationToken.None);

    var captured = JsonSerializer.Deserialize<string[]>(
                       File.ReadAllText(capturePath))
                   ?? throw new Exception("captured arguments are invalid");
    Assert(
        captured.SequenceEqual(new[] { payload }),
        "recursive previous-notify pair must be removed before forwarding");
});

await RunAsync("non-Codex previous-notify is preserved", async () =>
{
    using var temp = new TempDirectory();
    var capturePath = Path.Combine(temp.Path, "arguments.json");
    var executable = Environment.ProcessPath
                     ?? throw new Exception("self-test executable path is missing");
    var nestedNotifier = JsonSerializer.Serialize(new[]
    {
        "other-notifier.exe",
        "turn-ended"
    });
    const string payload = "{\"type\":\"agent-turn-complete\"}";

    await CodexNotifyForwarder.RunAsync(
        new[]
        {
            executable,
            "--capture-arguments",
            capturePath,
            "--previous-notify",
            nestedNotifier
        },
        payload,
        _ => { },
        CancellationToken.None);

    var captured = JsonSerializer.Deserialize<string[]>(
                       File.ReadAllText(capturePath))
                   ?? throw new Exception("captured arguments are invalid");
    Assert(
        captured.SequenceEqual(new[]
        {
            "--previous-notify",
            nestedNotifier,
            payload
        }),
        "non-Codex previous-notify pair must remain unchanged");
});

await RunAsync("direct CodexNotif forwarding command is blocked", async () =>
{
    var logs = new List<string>();
    var executable = Environment.ProcessPath
                     ?? throw new Exception("self-test executable path is missing");

    await CodexNotifyForwarder.RunAsync(
        new[]
        {
            executable,
            CodexNotifyConfiguration.NotifyArgument
        },
        "{\"type\":\"agent-turn-complete\"}",
        logs.Add,
        CancellationToken.None);

    Assert(
        logs.Any(message => message.Contains(
            "阻止",
            StringComparison.Ordinal)),
        "direct CodexNotif recursion must be blocked and logged");
});

await RunAsync("failed previous notifier is never logged as successful", async () =>
{
    using var temp = new TempDirectory();
    var logs = new List<string>();
    const string payload = "{\"type\":\"agent-turn-complete\"}";

    await CodexNotifyRunner.RunAsync(
        payload,
        "D_TEST",
        new AppSettings(),
        (_, _, _) => Task.CompletedTask,
        (json, cancellationToken) =>
            CodexNotifyForwarder.RunAsync(
                new[] { Path.Combine(temp.Path, "missing-notifier.exe") },
                json,
                logs.Add,
                cancellationToken),
        logs.Add,
        CancellationToken.None);

    Assert(
        logs.Any(line => line.Contains("失败", StringComparison.Ordinal)),
        "a missing previous notifier must be logged as failed");
    Assert(
        !logs.Any(line => line.Contains(
            "原通知程序转发成功",
            StringComparison.Ordinal)),
        "a failed previous notifier must never be logged as successful");
});

Run("hook log remains bounded", () =>
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "hook.log");

    for (var index = 0; index < 40; index++)
        HookLog.Write(path, $"record-{index:D2}-xxxxxxxxxxxxxxxx", maxBytes: 128);

    Assert(new FileInfo(path).Length <= 256, "hook log must remain bounded");
    Assert(File.ReadAllText(path).Contains("record-39"), "newest log record must remain");
});

if (args is ["--check-exe", var executablePath])
{
    await RunAsync("published executable handles Hook without a window", async () =>
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = Path.GetFullPath(executablePath),
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            }
        };
        process.StartInfo.ArgumentList.Add("--codex-stop-hook");

        Assert(process.Start(), "AgentPager process must start");
        await process.StandardInput.WriteAsync("""{"hook_event_name":"Unknown"}""");
        process.StandardInput.Close();

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));

        try
        {
            await process.WaitForExitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            throw new Exception("Hook process did not exit within three seconds");
        }

        var output = await process.StandardOutput.ReadToEndAsync();
        Assert(process.ExitCode == 0, "Hook process must exit zero");
        AssertContinueOutput(output);
    });

    await RunAsync("published executable handles notify without a window", async () =>
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.GetFullPath(executablePath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        startInfo.ArgumentList.Add("--codex-notify");
        startInfo.ArgumentList.Add("{\"type\":\"ignored-self-test\"}");

        using var process = Process.Start(startInfo)
            ?? throw new Exception("notify process did not start");

        await WaitForExitOrKillAsync(
            process,
            TimeSpan.FromSeconds(3),
            "notify process did not exit within three seconds");

        Assert(process.ExitCode == 0, "ignored notify must exit zero");
        Assert(
            process.MainWindowHandle == IntPtr.Zero,
            "notify mode must never create a main window");
    });
}

if (args is ["--check-ui", var uiExecutablePath])
{
    await RunAsync("normal executable launch creates the main window", async () =>
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = Path.GetFullPath(uiExecutablePath),
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Normal
        }) ?? throw new Exception("AgentPager process did not start");

        try
        {
            var deadline = DateTime.UtcNow.AddSeconds(5);

            while (DateTime.UtcNow < deadline && !process.HasExited)
            {
                process.Refresh();

                if (process.MainWindowHandle != IntPtr.Zero)
                    return;

                await Task.Delay(100);
            }

            throw new Exception("normal launch did not create a main window");
        }
        finally
        {
            if (!process.HasExited)
            {
                process.CloseMainWindow();

                using var exitTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));

                try
                {
                    await process.WaitForExitAsync(exitTimeout.Token);
                }
                catch (OperationCanceledException)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
        }
    });
}

if (args is ["--install-hook", var hooksPath, var hookExecutablePath])
{
    Run("installs requested user hook", () =>
    {
        CodexHookConfiguration.Install(
            Path.GetFullPath(hooksPath),
            Path.GetFullPath(hookExecutablePath));

        Assert(
            CodexHookConfiguration.GetStatus(hooksPath, hookExecutablePath)
                == CodexHookConfigurationStatus.Installed,
            "installed user hook must be detected");
    });
}

if (args is ["--install-notify", var notifyExecutablePath])
{
    await RunAsync("product install and restore modes are reversible", async () =>
    {
        using var temp = new TempDirectory();
        var config = Path.Combine(temp.Path, "config.toml");
        var state = Path.Combine(temp.Path, "state.json");
        const string original =
            "model = \"gpt-5\"\n"
            + "notify = [\"old.exe\"]\n";
        File.WriteAllText(config, original);

        var installInfo = new ProcessStartInfo
        {
            FileName = Path.GetFullPath(notifyExecutablePath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        installInfo.ArgumentList.Add("--install-codex-notify");
        installInfo.ArgumentList.Add(config);
        installInfo.ArgumentList.Add(state);

        using (var install = Process.Start(installInfo)
               ?? throw new Exception("install process did not start"))
        {
            await WaitForExitOrKillAsync(
                install,
                TimeSpan.FromSeconds(3),
                "install process did not exit within three seconds");
            Assert(install.ExitCode == 0, "product install mode must exit zero");
        }

        Assert(
            Count(File.ReadAllText(config), "--codex-notify") == 1,
            "product install mode must configure exactly once");

        var restoreInfo = new ProcessStartInfo
        {
            FileName = Path.GetFullPath(notifyExecutablePath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        restoreInfo.ArgumentList.Add("--restore-codex-notify");
        restoreInfo.ArgumentList.Add(config);
        restoreInfo.ArgumentList.Add(state);

        using (var restore = Process.Start(restoreInfo)
               ?? throw new Exception("restore process did not start"))
        {
            await WaitForExitOrKillAsync(
                restore,
                TimeSpan.FromSeconds(3),
                "restore process did not exit within three seconds");
            Assert(restore.ExitCode == 0, "product restore mode must exit zero");
        }

        Assert(
            File.ReadAllText(config) == original,
            "product restore mode must restore original content");
    });
}

if (args is ["--check-scripts", var repositoryPath, var scriptExecutablePath])
{
    await RunAsync("install and restore scripts are idempotent and reversible", async () =>
    {
        using var temp = new TempDirectory();
        var config = Path.Combine(temp.Path, "config.toml");
        var state = Path.Combine(temp.Path, "state.json");
        var installScript = Path.Combine(
            repositoryPath,
            "scripts",
            "Install-CodexNotifNotify.ps1");
        var restoreScript = Path.Combine(
            repositoryPath,
            "scripts",
            "Restore-CodexNotifNotify.ps1");
        const string original =
            "model = \"gpt-5\"\r\n"
            + "notify = [\"old.exe\", \"arg with spaces\"]\r\n";
        File.WriteAllText(config, original);
        var originalHash = Convert.ToHexString(
            System.Security.Cryptography.SHA256.HashData(
                File.ReadAllBytes(config)));

        await RunPowerShellScriptAsync(
            installScript,
            scriptExecutablePath,
            config,
            state);
        await RunPowerShellScriptAsync(
            installScript,
            scriptExecutablePath,
            config,
            state);

        Assert(
            Count(File.ReadAllText(config), "--codex-notify") == 1,
            "double script install must remain idempotent");

        await RunPowerShellScriptAsync(
            restoreScript,
            scriptExecutablePath,
            config,
            state);
        var restoredHash = Convert.ToHexString(
            System.Security.Cryptography.SHA256.HashData(
                File.ReadAllBytes(config)));

        Assert(
            restoredHash == originalHash,
            "script restore must reproduce the original config hash");
    });
}

if (args is ["--invoke-notify-base64", var invocationExecutablePath, var encodedPayload])
{
    await RunAsync("published executable accepts an explicit notify payload", async () =>
    {
        var invocationPayload = Encoding.UTF8.GetString(
            Convert.FromBase64String(encodedPayload));
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.GetFullPath(invocationExecutablePath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        startInfo.ArgumentList.Add("--codex-notify");
        startInfo.ArgumentList.Add(invocationPayload);

        using var process = Process.Start(startInfo)
            ?? throw new Exception("notify invocation did not start");
        await WaitForExitOrKillAsync(
            process,
            TimeSpan.FromSeconds(30),
            "notify invocation did not exit within thirty seconds");
        Assert(process.ExitCode == 0, "notify invocation must exit zero");
        Assert(
            process.MainWindowHandle == IntPtr.Zero,
            "notify invocation must remain headless");
    });
}

if (failures.Count > 0)
{
    foreach (var failure in failures)
        Console.Error.WriteLine("FAIL: " + failure);

    return 1;
}

Console.WriteLine("PASS: all self-tests");
return 0;

void Run(string name, Action test)
{
    try
    {
        test();
        Console.WriteLine("PASS: " + name);
    }
    catch (Exception ex)
    {
        failures.Add(name + " - " + ex.Message);
    }
}

async Task RunAsync(string name, Func<Task> test)
{
    try
    {
        await test();
        Console.WriteLine("PASS: " + name);
    }
    catch (Exception ex)
    {
        failures.Add(name + " - " + ex.Message);
    }
}

static AppSettings BoundSettings()
{
    return new AppSettings
    {
        DeviceToken = "token",
        BoundEmail = "bound@example.test"
    };
}

static void AssertContinueOutput(string output)
{
    using var document = JsonDocument.Parse(output);
    Assert(
        document.RootElement.GetProperty("continue").GetBoolean(),
        "hook output must contain continue=true");
}

static void Assert(bool condition, string message)
{
    if (!condition)
        throw new Exception(message);
}

static void AssertThrows<TException>(Action action)
    where TException : Exception
{
    try
    {
        action();
    }
    catch (TException)
    {
        return;
    }

    throw new Exception($"expected {typeof(TException).Name}");
}

static int Count(string value, string needle)
{
    var count = 0;
    var offset = 0;

    while ((offset = value.IndexOf(needle, offset, StringComparison.Ordinal)) >= 0)
    {
        count++;
        offset += needle.Length;
    }

    return count;
}

static async Task WaitForExitOrKillAsync(
    Process process,
    TimeSpan timeout,
    string timeoutMessage)
{
    using var cancellation = new CancellationTokenSource(timeout);

    try
    {
        await process.WaitForExitAsync(cancellation.Token);
    }
    catch (OperationCanceledException)
    {
        if (!process.HasExited)
            process.Kill(entireProcessTree: true);

        await process.WaitForExitAsync();
        throw new Exception(timeoutMessage);
    }
}

static async Task RunPowerShellScriptAsync(
    string scriptPath,
    string executablePath,
    string configPath,
    string statePath)
{
    var startInfo = new ProcessStartInfo
    {
        FileName = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe"),
        UseShellExecute = false,
        CreateNoWindow = true,
        RedirectStandardError = true,
        RedirectStandardOutput = true
    };

    foreach (var argument in new[]
             {
                 "-NoProfile",
                 "-ExecutionPolicy",
                 "Bypass",
                 "-File",
                 scriptPath,
                 "-ExecutablePath",
                 executablePath,
                 "-ConfigPath",
                 configPath,
                 "-StatePath",
                 statePath
             })
    {
        startInfo.ArgumentList.Add(argument);
    }

    using var process = Process.Start(startInfo)
        ?? throw new Exception("PowerShell script process did not start");
    await WaitForExitOrKillAsync(
        process,
        TimeSpan.FromSeconds(10),
        "PowerShell script did not exit within ten seconds");

    if (process.ExitCode != 0)
    {
        throw new Exception(
            $"PowerShell script failed with {process.ExitCode}: "
            + await process.StandardError.ReadToEndAsync());
    }
}

sealed class CaptureHttpHandler : HttpMessageHandler
{
    public List<CapturedRequest> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        request.Headers.TryGetValues(
            ServerAccessKeyResolver.HeaderName,
            out var accessKeyValues);

        Requests.Add(new CapturedRequest(
            request.RequestUri?.AbsolutePath ?? "",
            accessKeyValues?.SingleOrDefault(),
            request.Headers.Authorization?.Scheme,
            request.Headers.Authorization?.Parameter));

        var json = request.RequestUri?.AbsolutePath switch
        {
            "/health" => "{\"ok\":true}",
            "/api/v1/bind/create" =>
                "{\"bindId\":\"B_TEST\",\"pollToken\":\"poll-token\",\"expiresAt\":\"2030-01-01T00:00:00Z\"}",
            "/api/v1/bind/B_TEST" =>
                "{\"status\":\"verified\",\"deviceToken\":\"device-token\",\"email\":\"user@example.test\"}",
            "/api/v1/auth/check" =>
                "{\"accessKeyAuthenticated\":true,\"deviceAuthenticated\":true}",
            _ => "{\"ok\":true}"
        };

        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        });
    }
}

sealed record CapturedRequest(
    string Path,
    string? AccessKey,
    string? AuthorizationScheme,
    string? AuthorizationParameter);

sealed class TempDirectory : IDisposable
{
    public TempDirectory()
    {
        Path = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "AgentPager-SelfTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        Directory.Delete(Path, recursive: true);
    }
}
