using System.IO;
using System.Net.Mail;
using System.Windows;
using AgentPager.Models;
using AgentPager.Services;

namespace AgentPager;

public partial class MainWindow : Window
{
    private readonly string _deviceId;
    private readonly SettingsService _settingsService = new();
    private RelayApiClient _relay;
    private readonly CodexDetector _codexDetector;
    private readonly string _codexConfigPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".codex",
        "config.toml");
    private readonly string _codexNotifyStatePath = Path.Combine(
        Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData),
        "CodexNotif",
        "codex-notify-state.json");

    private AppSettings _settings;
    private CancellationTokenSource? _bindingCts;

    public MainWindow()
    {
        InitializeComponent();

        _deviceId = new DeviceIdentityService().GetOrCreate();
        _settings = _settingsService.Load();
        ServerAddressResolution server;
        string? serverConfigurationError = null;

        try
        {
            server = ServerAddressResolver.Resolve(
                _settings.ServerBaseUrl);
        }
        catch (ArgumentException ex)
        {
            server = ServerAddressResolver.Resolve("", "");
            serverConfigurationError = ex.Message;
        }

        _relay = new RelayApiClient(
            server.BaseUrl,
            ServerAccessKeyResolver.ReadOptional());
        ServerUrlTextBox.Text = serverConfigurationError is null
            ? server.BaseUrl
            : _settings.ServerBaseUrl;
        UpdateServerSource(server);
        ServerSettingsStatusText.Text = serverConfigurationError is null
            ? "当前地址已加载。"
            : "已保存的地址无效：" + serverConfigurationError;
        UpdateAccessKeyStatus();

        DeviceIdText.Text = _deviceId;

        if (!string.IsNullOrWhiteSpace(_settings.BoundEmail))
            EmailTextBox.Text = _settings.BoundEmail;
        else if (!string.IsNullOrWhiteSpace(_settings.PendingEmail))
            EmailTextBox.Text = _settings.PendingEmail;

        _codexDetector = new CodexDetector(_deviceId);
        _codexDetector.Completed += CodexDetector_Completed;
        _codexDetector.Start();

        Loaded += MainWindow_Loaded;
        Closed += MainWindow_Closed;

        UpdateBindingUi();
        UpdateCodexNotifyUi();
    }

    private async void MainWindow_Loaded(
        object sender,
        RoutedEventArgs e)
    {
        await CheckServerAsync();

        if (HasUsablePendingBinding())
        {
            BindingStatusText.Text =
                "检测到未完成的邮箱绑定，正在继续等待验证结果。";

            StartBindingPolling();
        }
        else if (!string.IsNullOrWhiteSpace(_settings.PendingBindId))
        {
            ClearPendingBinding();
        }

        OfferCodexNotifyInstall();
    }

    private void MainWindow_Closed(
        object? sender,
        EventArgs e)
    {
        _bindingCts?.Cancel();
        _bindingCts?.Dispose();

        _codexDetector.Stop();
        _relay.Dispose();
    }

    private async void BindButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        var email = EmailTextBox.Text.Trim();

        if (!IsValidEmail(email))
        {
            BindingStatusText.Text =
                "请输入有效的邮箱地址。";
            return;
        }

        BindButton.IsEnabled = false;
        BindingProgress.Visibility = Visibility.Visible;
        BindingStatusText.Text =
            "正在请求服务器发送验证邮件...";

        try
        {
            var created = await _relay.CreateBindingAsync(
                _deviceId,
                email,
                string.IsNullOrWhiteSpace(_settings.DeviceToken)
                    ? null
                    : _settings.DeviceToken);

            _settings.PendingBindId = created.BindId;
            _settings.PendingPollToken = created.PollToken;
            _settings.PendingEmail = email;
            _settings.PendingExpiresAt = created.ExpiresAt;

            _settingsService.Save(_settings);

            AddEvent(
                "验证邮件已发送",
                email);

            BindingStatusText.Text =
                $"验证邮件已发送到 {email}。请打开邮件并点击验证链接，本窗口会自动检测结果。";

            StartBindingPolling();
        }
        catch (Exception ex)
        {
            BindingProgress.Visibility = Visibility.Collapsed;
            BindingStatusText.Text =
                "发送验证邮件失败：" + ex.Message;

            AddEvent(
                "邮箱绑定失败",
                ex.Message);
        }
        finally
        {
            BindButton.IsEnabled = true;
        }
    }

    private void StartBindingPolling()
    {
        _bindingCts?.Cancel();
        _bindingCts?.Dispose();

        _bindingCts = new CancellationTokenSource();

        BindingProgress.Visibility = Visibility.Visible;

        _ = PollBindingAsync(
            _bindingCts.Token);
    }

    private async Task PollBindingAsync(
        CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (!HasUsablePendingBinding())
                {
                    ClearPendingBinding();

                    BindingStatusText.Text =
                        "验证链接已经过期，请重新发送验证邮件。";

                    BindingProgress.Visibility =
                        Visibility.Collapsed;

                    return;
                }

                try
                {
                    var status =
                        await _relay.GetBindingStatusAsync(
                            _settings.PendingBindId,
                            _settings.PendingPollToken,
                            cancellationToken);

                    if (string.Equals(
                            status.Status,
                            "bound",
                            StringComparison.OrdinalIgnoreCase)
                        && !string.IsNullOrWhiteSpace(
                            status.DeviceToken))
                    {
                        _settings.DeviceToken =
                            status.DeviceToken;

                        _settings.BoundEmail =
                            status.Email
                            ?? _settings.PendingEmail;

                        ClearPendingFieldsOnly();

                        _settingsService.Save(_settings);

                        BindingProgress.Visibility =
                            Visibility.Collapsed;

                        BindingStatusText.Text =
                            $"邮箱绑定成功：{_settings.BoundEmail}";

                        StatusText.Text =
                            "设备已取得独立 Device Token，可以发送通知。";

                        AddEvent(
                            "邮箱绑定成功",
                            _settings.BoundEmail);

                        UpdateBindingUi();
                        return;
                    }

                    var remaining =
                        _settings.PendingExpiresAt!.Value
                        - DateTimeOffset.UtcNow;

                    BindingStatusText.Text =
                        $"等待邮箱验证：{_settings.PendingEmail}（剩余约 {Math.Max(0, (int)remaining.TotalMinutes)} 分钟）";
                }
                catch (OperationCanceledException)
                {
                    return;
                }
                catch (Exception ex)
                {
                    BindingStatusText.Text =
                        "等待验证中，服务器暂时返回：" + ex.Message;
                }

                await Task.Delay(
                    TimeSpan.FromSeconds(2),
                    cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // 正常取消。
        }
    }

    private async void TestNotificationButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        if (!EnsureBound())
            return;

        TestNotificationButton.IsEnabled = false;
        StatusText.Text = "正在发送测试通知...";

        try
        {
            var testEvent = new AgentEvent(
                _deviceId,
                "agentpager",
                "notification.test",
                DateTimeOffset.Now);

            await _relay.SendEventAsync(
                testEvent,
                _settings.DeviceToken);

            StatusText.Text =
                $"测试通知已提交，请检查 {_settings.BoundEmail}。";

            AddEvent(
                "测试通知已发送",
                _settings.BoundEmail);
        }
        catch (Exception ex)
        {
            StatusText.Text =
                "测试通知失败：" + ex.Message;

            AddEvent(
                "测试通知失败",
                ex.Message);
        }
        finally
        {
            TestNotificationButton.IsEnabled = true;
        }
    }

    private void SimulateCompletedButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        _codexDetector.SimulateCompleted();
    }

    private void EnableCodexNotifyButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        InstallCodexNotify(showSuccessDialog: true);
    }

    private void OfferCodexNotifyInstall()
    {
        var executablePath = Environment.ProcessPath;

        if (string.IsNullOrWhiteSpace(executablePath))
            return;

        var status = CodexNotifyConfiguration.GetStatus(
            _codexConfigPath,
            executablePath);

        if (!CodexNotifyConfiguration.ShouldOfferInstall(
                status,
                _settings.CodexNotifyPromptDismissed))
        {
            return;
        }

        var choice = MessageBox.Show(
            this,
            "是否启用 Codex 主任务完成邮件？\n\n"
            + "CodexNotif 将先备份 Codex 配置，再安装原生完成通知。"
            + "现有 Computer Use 或其他通知程序会继续运行。\n\n"
            + "不读取或上传 Prompt、源代码和对话正文。",
            "启用 Codex 完成通知",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (choice == MessageBoxResult.Yes)
        {
            InstallCodexNotify(showSuccessDialog: true);
            return;
        }

        _settings.CodexNotifyPromptDismissed = true;
        _settingsService.Save(_settings);
    }

    private void InstallCodexNotify(bool showSuccessDialog)
    {
        var executablePath = Environment.ProcessPath;

        if (string.IsNullOrWhiteSpace(executablePath))
        {
            DetectorStatusText.Text = "配置失败";
            DetectorDetailText.Text = "无法确定 CodexNotif.exe 路径。";
            return;
        }

        try
        {
            CodexNotifyConfiguration.Install(
                _codexConfigPath,
                executablePath,
                _codexNotifyStatePath);

            _settings.CodexNotifyPromptDismissed = false;
            _settingsService.Save(_settings);
            UpdateCodexNotifyUi();

            if (showSuccessDialog)
            {
                MessageBox.Show(
                    this,
                    "Codex 完成通知已启用。无需进入 /hooks。\n\n"
                    + "请重新打开 Codex；下次主任务停止等待时将自动发送邮件。",
                    "CodexNotif",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            DetectorStatusText.Text = "配置异常";
            DetectorDetailText.Text = ex.Message;
        }
    }

    private async void CheckServerButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        await CheckServerAsync();
    }

    private async void SaveServerButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        var previousBaseUrl = _settings.ServerBaseUrl;
        var enteredAccessKey = AccessKeyPasswordBox.Password;
        var accessKeyChanged = false;
        SetServerButtonsEnabled(false);

        try
        {
            var normalized = ServerAddressResolver.Normalize(
                ServerUrlTextBox.Text);
            string? validatedAccessKey = null;

            if (!string.IsNullOrEmpty(enteredAccessKey))
            {
                validatedAccessKey =
                    ServerAccessKeyResolver.Validate(enteredAccessKey);
            }

            _settings.ServerBaseUrl = normalized;
            _settingsService.Save(_settings);

            if (validatedAccessKey is not null)
            {
                ServerAccessKeyResolver.SaveForCurrentUser(
                    validatedAccessKey);
                AccessKeyPasswordBox.Clear();
                accessKeyChanged = true;
            }

            var server = ServerAddressResolver.Resolve(
                _settings.ServerBaseUrl);
            ReplaceRelay(server);
            ServerSettingsStatusText.Text =
                accessKeyChanged
                    ? "服务器地址与访问密钥已保存，正在验证..."
                    : "服务器设置已保存，正在验证...";

            var ok = await CheckServerAsync();
            ServerSettingsStatusText.Text = ok
                ? accessKeyChanged
                    ? "服务器地址与访问密钥已保存，认证正常。"
                    : "服务器设置已保存，认证正常。"
                : accessKeyChanged
                    ? "访问密钥已保存，但服务器认证失败；请确认宝塔使用相同密钥。"
                    : "服务器设置已保存，但当前认证失败。";
        }
        catch (ArgumentException ex)
        {
            _settings.ServerBaseUrl = previousBaseUrl;
            ServerSettingsStatusText.Text = ex.Message;
        }
        catch (Exception ex)
        {
            _settings.ServerBaseUrl = previousBaseUrl;
            ServerSettingsStatusText.Text =
                "服务器设置保存失败：" + ex.Message;
        }
        finally
        {
            SetServerButtonsEnabled(true);
        }
    }

    private async void RestoreServerButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        var previousBaseUrl = _settings.ServerBaseUrl;
        SetServerButtonsEnabled(false);

        try
        {
            var server = ServerAddressResolver.Resolve(
                "",
                Environment.GetEnvironmentVariable(
                    "CODEXNOTIF_SERVER_URL"));
            _settings.ServerBaseUrl = "";
            _settingsService.Save(_settings);
            ReplaceRelay(server);
            var ok = await CheckServerAsync();
            ServerSettingsStatusText.Text = ok
                ? "已恢复回退配置，连接正常。"
                : "已恢复回退配置，但当前无法连接。";
        }
        catch (Exception ex)
        {
            _settings.ServerBaseUrl = previousBaseUrl;
            ServerSettingsStatusText.Text =
                "恢复默认设置失败：" + ex.Message;
        }
        finally
        {
            SetServerButtonsEnabled(true);
        }
    }

    private void ReplaceRelay(ServerAddressResolution server)
    {
        var replacement = new RelayApiClient(
            server.BaseUrl,
            ServerAccessKeyResolver.ReadOptional());
        var previous = _relay;
        _relay = replacement;
        previous.Dispose();

        ServerUrlTextBox.Text = server.BaseUrl;
        UpdateServerSource(server);
        UpdateAccessKeyStatus();
    }

    private void UpdateServerSource(ServerAddressResolution server)
    {
        var source = server.Source switch
        {
            ServerAddressSource.ClientSettings => "客户端设置",
            ServerAddressSource.EnvironmentVariable => "环境变量",
            _ => "内置默认值"
        };

        ServerSourceText.Text =
            $"当前使用：{server.BaseUrl}（{source}）";
    }

    private void SetServerButtonsEnabled(bool enabled)
    {
        SaveServerButton.IsEnabled = enabled;
        RestoreServerButton.IsEnabled = enabled;
    }

    private void UpdateAccessKeyStatus()
    {
        AccessKeyStatusText.Text = _relay.HasValidAccessKey
            ? $"访问密钥：已从环境变量 {ServerAccessKeyResolver.EnvironmentVariableName} 加载。"
            : $"访问密钥：未配置有效的 {ServerAccessKeyResolver.EnvironmentVariableName}。";
    }

    private async Task<bool> CheckServerAsync()
    {
        ServerStatusText.Text =
            "正在检查服务器...";

        try
        {
            var authentication = await _relay.CheckAuthenticationAsync(
                _deviceId,
                _settings.DeviceToken);
            var ok = authentication.AccessKeyAuthenticated;

            ServerStatusText.Text = ok
                ? "服务器在线"
                : "服务器异常";
            AccessKeyStatusText.Text = authentication.DeviceAuthenticated
                ? "访问密钥：服务器验证通过；设备 Token 验证通过。"
                : string.IsNullOrWhiteSpace(_settings.DeviceToken)
                    ? "访问密钥：服务器验证通过；设备尚未绑定。"
                    : "访问密钥：服务器验证通过；设备 Token 未通过，请重新绑定。";

            AddEvent(
                ok ? "服务器在线" : "服务器异常",
                authentication.DeviceAuthenticated
                    ? _relay.ServerBaseUrl + " · 双层认证通过"
                    : _relay.ServerBaseUrl + " · 访问密钥通过");

            return ok;
        }
        catch (Exception ex)
        {
            ServerStatusText.Text =
                "服务器不可用";
            UpdateAccessKeyStatus();

            StatusText.Text =
                "服务器检查失败：" + ex.Message;

            return false;
        }
    }

    private async void CodexDetector_Completed(
        object? sender,
        AgentEvent e)
    {
        AddEvent(
            "Codex 已完成",
            $"{e.EventType} · {e.Timestamp:HH:mm:ss}");

        if (!EnsureBound(showDialog: false))
        {
            StatusText.Text =
                "检测到 Codex 完成，但当前尚未绑定通知邮箱。";
            return;
        }

        StatusText.Text =
            "检测到 Codex 完成，正在发送邮件通知...";

        try
        {
            await _relay.SendEventAsync(
                e,
                _settings.DeviceToken);

            StatusText.Text =
                $"完成通知已提交到 {_settings.BoundEmail}。";

            AddEvent(
                "完成通知已发送",
                _settings.BoundEmail);
        }
        catch (Exception ex)
        {
            StatusText.Text =
                "完成通知发送失败：" + ex.Message;

            AddEvent(
                "完成通知失败",
                ex.Message);
        }
    }

    private bool EnsureBound(
        bool showDialog = true)
    {
        var bound =
            !string.IsNullOrWhiteSpace(
                _settings.DeviceToken)
            && !string.IsNullOrWhiteSpace(
                _settings.BoundEmail);

        if (!bound && showDialog)
        {
            MessageBox.Show(
                this,
                "请先完成邮箱绑定。",
                "CodexNotif",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }

        return bound;
    }

    private void UpdateBindingUi()
    {
        if (EnsureBound(showDialog: false))
        {
            EmailSummaryText.Text =
                _settings.BoundEmail;

            BindingSummaryText.Text =
                "已绑定，可接收 CodexNotif 通知";

            BindingStatusText.Text =
                $"当前绑定邮箱：{_settings.BoundEmail}";

            BindButton.Content =
                "更换 / 重新验证邮箱";

            TestNotificationButton.IsEnabled = true;
            SimulateCompletedButton.IsEnabled = true;
        }
        else
        {
            EmailSummaryText.Text =
                "尚未绑定";

            BindingSummaryText.Text =
                "请输入邮箱并完成验证";

            BindButton.Content =
                "发送验证邮件";

            TestNotificationButton.IsEnabled = false;
            SimulateCompletedButton.IsEnabled = true;
        }
    }

    private void UpdateCodexNotifyUi()
    {
        var executablePath = Environment.ProcessPath;

        if (string.IsNullOrWhiteSpace(executablePath))
        {
            DetectorStatusText.Text = "配置异常";
            DetectorDetailText.Text = "无法确定 CodexNotif.exe 路径。";
            EnableCodexNotifyButton.IsEnabled = false;
            return;
        }

        var status = CodexNotifyConfiguration.GetStatus(
            _codexConfigPath,
            executablePath);

        switch (status)
        {
            case CodexNotifyConfigurationStatus.Installed:
                DetectorStatusText.Text = "Codex 完成通知已启用";
                DetectorDetailText.Text = "主任务停止等待后将自动发邮件；原有通知程序仍会继续运行。";
                EnableCodexNotifyButton.Content = "已启用";
                EnableCodexNotifyButton.IsEnabled = false;
                break;

            case CodexNotifyConfigurationStatus.Invalid:
                DetectorStatusText.Text = "Codex 配置需要检查";
                DetectorDetailText.Text = "CodexNotif 未覆盖无法安全解析的 notify 配置。";
                EnableCodexNotifyButton.Content = "配置不可自动修改";
                EnableCodexNotifyButton.IsEnabled = false;
                break;

            default:
                DetectorStatusText.Text = "尚未启用";
                DetectorDetailText.Text = "启用后由 Codex 原生完成事件触发，不需要 Hook 信任。";
                EnableCodexNotifyButton.Content = "启用 Codex 完成通知";
                EnableCodexNotifyButton.IsEnabled = true;
                break;
        }
    }

    private bool HasUsablePendingBinding()
    {
        return
            !string.IsNullOrWhiteSpace(
                _settings.PendingBindId)
            && !string.IsNullOrWhiteSpace(
                _settings.PendingPollToken)
            && !string.IsNullOrWhiteSpace(
                _settings.PendingEmail)
            && _settings.PendingExpiresAt.HasValue
            && _settings.PendingExpiresAt.Value
               > DateTimeOffset.UtcNow;
    }

    private void ClearPendingBinding()
    {
        ClearPendingFieldsOnly();
        _settingsService.Save(_settings);

        BindingProgress.Visibility =
            Visibility.Collapsed;
    }

    private void ClearPendingFieldsOnly()
    {
        _settings.PendingBindId = "";
        _settings.PendingPollToken = "";
        _settings.PendingEmail = "";
        _settings.PendingExpiresAt = null;
    }

    private static bool IsValidEmail(
        string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return false;

        try
        {
            var address = new MailAddress(value);

            return string.Equals(
                address.Address,
                value,
                StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private void AddEvent(
        string title,
        string detail)
    {
        Dispatcher.Invoke(() =>
        {
            EventList.Items.Insert(
                0,
                $"{DateTime.Now:HH:mm:ss}  {title}  —  {detail}");

            while (EventList.Items.Count > 30)
                EventList.Items.RemoveAt(
                    EventList.Items.Count - 1);
        });
    }
}
