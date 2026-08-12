import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/app_config.dart';
import '../models/mail_rule.dart';
import '../models/monitor_health.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../services/qq_mail_service.dart';
import '../services/secure_config_service.dart';
import 'rule_editor_page.dart';

const _manualMailboxChoice = '\u0000manual-mailbox';

String monitorServiceStatus({
  required bool running,
  required MonitorHealth health,
  required DateTime now,
}) {
  if (!running) return '后台监听未启动';
  if (health.lastScanAt == null) {
    return '后台监听服务运行中，等待首次 IMAP 检查';
  }
  if (health.isStale(now)) {
    return '前台服务仍在，但 IMAP 检查已超过 90 秒';
  }
  return '后台监听服务运行中';
}

bool shouldRecoverMonitoring(
  AppConfig config, {
  required bool serviceRunning,
}) {
  return config.monitoringEnabled && !serviceRunning;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialConfig,
    this.initialServiceRunning,
    this.initialMonitorHealth,
  });

  final AppConfig? initialConfig;
  final bool? initialServiceRunning;
  final MonitorHealth? initialMonitorHealth;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _authController = TextEditingController();

  AppConfig _config = const AppConfig();
  bool _loading = true;
  bool _testing = false;
  bool _choosingMailbox = false;
  bool _serviceRunning = false;
  int _selectedTab = 0;
  String _status = '正在加载…';
  String _lastMail = '暂无';
  String _lastScan = '尚未检查';
  MonitorHealth _monitorHealth = const MonitorHealth();
  Timer? _serviceStateTimer;

  bool get _usesInjectedState =>
      widget.initialConfig != null || widget.initialServiceRunning != null;

  @override
  void initState() {
    super.initState();

    if (_usesInjectedState) {
      _config = widget.initialConfig ?? const AppConfig();
      _serviceRunning = widget.initialServiceRunning ?? false;
      _monitorHealth = widget.initialMonitorHealth ?? const MonitorHealth();
      _emailController.text = _config.email;
      _authController.text = _config.authCode;
      _lastScan = _monitorHealth.lastScanText.isEmpty
          ? '尚未检查'
          : _monitorHealth.lastScanText;
      _status = monitorServiceStatus(
        running: _serviceRunning,
        health: _monitorHealth,
        now: DateTime.now(),
      );
      _loading = false;
      return;
    }

    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);
    _load();
    _serviceStateTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshServiceState(),
    );
  }

  @override
  void dispose() {
    _serviceStateTimer?.cancel();
    if (!_usesInjectedState) {
      WidgetsBinding.instance.removeObserver(this);
      FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
    }
    _emailController.dispose();
    _authController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_usesInjectedState && state == AppLifecycleState.resumed) {
      _refreshServiceState();
    }
  }

  Future<void> _load() async {
    final config = await SecureConfigService.load();
    var running = await BackgroundService.isRunning();
    BackgroundStartResult? recoveryResult;
    if (shouldRecoverMonitoring(config, serviceRunning: running)) {
      recoveryResult = await BackgroundService.startOrRestart();
      running = recoveryResult.success;
    }
    final health = await BackgroundService.loadMonitorHealth();
    if (!mounted) return;

    setState(() {
      _config = config;
      _emailController.text = config.email;
      _authController.text = config.authCode;
      _serviceRunning = running;
      _monitorHealth = health;
      _lastScan = health.lastScanText.isEmpty ? '尚未检查' : health.lastScanText;
      _status = recoveryResult?.message ??
          monitorServiceStatus(
            running: running,
            health: health,
            now: DateTime.now(),
          );
      _loading = false;
    });
    await NotificationService.instance.initialize();
  }

  Future<void> _refreshServiceState() async {
    if (_usesInjectedState) return;
    final running = await BackgroundService.isRunning();
    final health = await BackgroundService.loadMonitorHealth();
    if (!mounted) return;

    final now = DateTime.now();
    final wasStale = _monitorHealth.isStale(now);
    final isStale = health.isStale(now);
    final runningChanged = _serviceRunning != running;

    setState(() {
      _serviceRunning = running;
      _monitorHealth = health;
      if (health.lastScanText.isNotEmpty) {
        _lastScan = health.lastScanText;
      }
      if (runningChanged || isStale || wasStale) {
        _status = monitorServiceStatus(
          running: running,
          health: health,
          now: now,
        );
      }
    });
  }

  void _onBackgroundData(Object data) {
    if (!mounted || data is! Map) return;

    final type = data['type']?.toString();
    final text = data['text']?.toString();
    setState(() {
      if (type == 'service' && data['running'] is bool) {
        _serviceRunning = data['running'] == true;
      }
      if (type == 'scan' && text != null) {
        _lastScan = text;
        _monitorHealth = MonitorHealth(
          lastScanAt: DateTime.now(),
          lastScanText: text,
        );
        _status = '后台监听服务运行中';
      } else if (type == 'mailboxFallback' && text != null) {
        _config = _config.copyWith(imapMailboxPath: '');
        _status = text;
      } else if (text != null && text.isNotEmpty) {
        _status = text;
      }
      if (type == 'match' || type == 'mail') {
        final sender = data['sender']?.toString() ?? '';
        final subject = data['subject']?.toString() ?? '';
        _lastMail = '${type == 'match' ? '已匹配' : '未匹配'}：$sender\n$subject';
      }
    });
  }

  Future<void> _saveCredentials() async {
    _config = _config.copyWith(
      email: _emailController.text.trim(),
      authCode: _authController.text.trim(),
    );
    await SecureConfigService.save(_config);
  }

  Future<void> _testLogin() async {
    setState(() {
      _testing = true;
      _status = '正在登录 QQ IMAP…';
    });

    try {
      await _saveCredentials();
      await QqMailService.testLogin(_config);
      if (!mounted) return;
      setState(() => _status = 'QQ 邮箱登录成功，IMAP 可正常读取');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录成功')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '登录失败：$error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _chooseMailbox() async {
    await _saveCredentials();
    if (!_config.hasCredentials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 QQ 邮箱和授权码')),
      );
      return;
    }

    setState(() {
      _choosingMailbox = true;
      _status = '正在读取 QQ IMAP 文件夹…';
    });

    try {
      final options = await QqMailService.listSelectableMailboxes(_config);
      if (!mounted) return;
      final currentPath = _config.imapMailboxPath.trim();
      final selectedPath = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 600),
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    '选择监听文件夹',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('只监听一个文件夹；不选择时使用根收件箱'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('手动指定文件夹'),
                  subtitle: const Text('QQ 未在列表显示自定义文件夹时使用'),
                  onTap: () => Navigator.of(sheetContext).pop(
                    _manualMailboxChoice,
                  ),
                ),
                if (!hasQqCustomMailboxOption(options))
                  const ListTile(
                    leading: Icon(Icons.warning_amber_rounded),
                    title: Text('QQ IMAP 未开放自定义文件夹'),
                    subtitle: Text(
                      '请先在 QQ 邮箱网页版的“收取选项”开启“收取我的文件夹”，保存后返回重试。',
                    ),
                  ),
                const Divider(height: 1),
                for (final option in options)
                  ListTile(
                    leading: Radio<String>(
                      value: option.isInbox ? '' : option.path,
                      groupValue: currentPath,
                      onChanged: (value) =>
                          Navigator.of(sheetContext).pop(value),
                    ),
                    title: Text(option.displayName),
                    subtitle:
                        !option.isInbox && option.displayName != option.path
                            ? Text(option.path)
                            : null,
                    onTap: () => Navigator.of(sheetContext).pop(
                      option.isInbox ? '' : option.path,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selectedPath == null || !mounted) return;

      var resolvedPath = selectedPath;
      if (selectedPath == _manualMailboxChoice) {
        final manualPath = await _askForMailboxPath(currentPath);
        if (manualPath == null || !mounted) return;

        setState(() => _status = '正在验证文件夹“$manualPath”…');
        try {
          await QqMailService.validateMailboxPath(_config, manualPath);
        } catch (error) {
          if (!mounted) return;
          final message = '文件夹验证失败：$error';
          setState(() => _status = message);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          return;
        }
        resolvedPath = manualPath;
      }

      _config = _config.copyWith(imapMailboxPath: resolvedPath);
      await SecureConfigService.save(_config);
      if (_serviceRunning) BackgroundService.reload();
      if (!mounted) return;
      setState(() {
        _status = resolvedPath.isEmpty
            ? '已改为监听根收件箱（INBOX）'
            : '已改为监听文件夹：$resolvedPath';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '读取文件夹失败：$error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取文件夹失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _choosingMailbox = false);
    }
  }

  Future<String?> _askForMailboxPath(String currentPath) async {
    final controller = TextEditingController(text: currentPath);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('手动指定文件夹'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'IMAP 文件夹名称',
              hintText: '请与 QQ 邮箱中的名称完全一致',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              final path = value.trim();
              if (path.isNotEmpty) Navigator.of(dialogContext).pop(path);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final path = controller.text.trim();
                if (path.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('文件夹名称不能为空')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(path);
              },
              child: const Text('验证并使用'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _toggleMonitoring(bool enabled) async {
    await _saveCredentials();
    if (enabled && !_config.hasCredentials) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 QQ 邮箱和授权码')),
      );
      return;
    }

    _config = _config.copyWith(monitoringEnabled: enabled);
    await SecureConfigService.save(_config);

    if (enabled) {
      await BackgroundService.requestRuntimePermissions();
      await NotificationService.instance.requestPermission();
      if (mounted) setState(() => _status = '正在启动后台监听服务…');

      final result = await BackgroundService.startOrRestart();
      if (!mounted) return;
      setState(() {
        _status = result.message;
        _serviceRunning = result.success;
      });
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } else {
      await BackgroundService.stop();
      if (!mounted) return;
      setState(() {
        _serviceRunning = false;
        _status = '后台监听已停止';
      });
    }
    await _refreshServiceState();
  }

  Future<void> _addRule() async {
    final outcome = await Navigator.of(context).push<RuleEditorOutcome>(
      MaterialPageRoute(builder: (_) => const RuleEditorPage()),
    );
    final rule = outcome?.rule;
    if (rule == null) return;
    await _persistRules([..._config.rules, rule]);
  }

  Future<void> _editRule(int index) async {
    final outcome = await Navigator.of(context).push<RuleEditorOutcome>(
      MaterialPageRoute(
        builder: (_) => RuleEditorPage(initial: _config.rules[index]),
      ),
    );
    if (outcome == null) return;

    final rules = [..._config.rules];
    if (outcome.isDeleted) {
      rules.removeAt(index);
    } else if (outcome.rule != null) {
      rules[index] = outcome.rule!;
    } else {
      return;
    }
    await _persistRules(rules);
  }

  Future<void> _setRuleEnabled(int index, bool enabled) async {
    final rules = [..._config.rules];
    rules[index] = rules[index].copyWith(enabled: enabled);
    await _persistRules(rules);
  }

  Future<void> _persistRules(List<MailRule> rules) async {
    _config = _config.copyWith(rules: rules);
    await SecureConfigService.save(_config);
    if (_serviceRunning) BackgroundService.reload();
    if (mounted) setState(() {});
  }

  Future<void> _requestBackgroundPermissions() async {
    await BackgroundService.requestRuntimePermissions();
    await NotificationService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _status = '通知权限已检查；应用退到后台时继续监听，从最近任务划掉后停止。';
    });
  }

  Future<void> _requestStrongAlertPermission() async {
    await NotificationService.instance.requestPermission();
    await NotificationService.instance.requestFullScreenPermission();
    if (!mounted) return;
    setState(() => _status = '已检查强提醒的通知与全屏显示权限');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(_selectedTab == 0 ? '提醒' : '设置'),
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildRemindersTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (value) => setState(() => _selectedTab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: '提醒',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );

    return _usesInjectedState ? scaffold : WithForegroundTask(child: scaffold);
  }

  Widget _buildRemindersTab() {
    final monitorHealthy =
        _serviceRunning && !_monitorHealth.isStale(DateTime.now());

    return ListView(
      key: const PageStorageKey('reminders'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _SettingsGroup(
          children: [
            ListTile(
              minVerticalPadding: 14,
              leading: CircleAvatar(
                backgroundColor: _serviceRunning
                    ? (monitorHealthy ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.16)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  monitorHealthy
                      ? Icons.check_circle_rounded
                      : (_serviceRunning
                          ? Icons.warning_amber_rounded
                          : Icons.pause_circle_outline_rounded),
                  color: monitorHealthy
                      ? Colors.green
                      : (_serviceRunning
                          ? Colors.orange
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              title: Text(
                monitorHealthy
                    ? '后台监听中'
                    : (_serviceRunning ? '后台监听需检查' : '后台监听已停止'),
              ),
              subtitle:
                  Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title: '提醒规则',
          action: IconButton.filledTonal(
            tooltip: '添加规则',
            onPressed: _addRule,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        if (_config.rules.isEmpty)
          _SettingsGroup(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '还没有提醒规则。\n可以按主题或发件人匹配，并为每条规则选择普通提醒或强提醒。',
                ),
              ),
            ],
          )
        else
          _SettingsGroup(
            children: [
              for (var index = 0; index < _config.rules.length; index++)
                _buildRuleTile(index),
            ],
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '第一条命中的规则决定通知方式和铃声。强提醒会持续响铃，直到你确认。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(title: '最近活动'),
        _SettingsGroup(
          children: [
            ListTile(
              title: const Text('IMAP 最近检查'),
              subtitle: Text(_lastScan),
            ),
            ListTile(
              title: const Text('最近捕获的邮件'),
              subtitle: Text(_lastMail),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRuleTile(int index) {
    final rule = _config.rules[index];
    final sound = rule.sound == AlertSound.systemLocal
        ? (rule.systemSoundTitle ?? '手机本地声音')
        : rule.sound.label;

    return ListTile(
      minVerticalPadding: 12,
      leading: Switch(
        value: rule.enabled,
        onChanged: (value) => _setRuleEnabled(index, value),
      ),
      title: Text('${rule.type.label}：${rule.pattern}'),
      subtitle: Text(
        '${rule.alertMode.label} · $sound${rule.enabled ? '' : ' · 已停用'}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _editRule(index),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _SectionHeader(title: 'QQ 邮箱账户'),
        _SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'QQ 邮箱',
                  hintText: 'name@example.com',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TextField(
                controller: _authController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'QQ 邮箱授权码',
                  helperText: '不是 QQ 登录密码',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('监听文件夹'),
              subtitle: Text(
                _config.imapMailboxPath.trim().isEmpty
                    ? '根收件箱（INBOX）'
                    : _config.imapMailboxPath,
              ),
              trailing: _choosingMailbox
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _choosingMailbox ? null : _chooseMailbox,
            ),
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: const Text('测试 QQ IMAP 登录'),
              trailing: _testing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _testing ? null : _testLogin,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '授权码保存在设备安全存储中。程序只读取新邮件的发件人和主题。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(title: '监听'),
        _SettingsGroup(
          children: [
            SwitchListTile(
              title: const Text('后台监听'),
              subtitle: Text(_serviceRunning ? '正在运行' : '当前已停止'),
              value: _config.monitoringEnabled,
              onChanged: _toggleMonitoring,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader(title: '系统权限'),
        _SettingsGroup(
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('强提醒全屏权限'),
              subtitle: const Text('允许来电式全屏显示；仍尊重免打扰'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _requestStrongAlertPermission,
            ),
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('通知与后台常驻'),
              subtitle: const Text('通知权限、电池优化和前台服务'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _requestBackgroundPermissions,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '小米 / HyperOS 通常还需在系统设置中手工允许“自启动”和“后台无限制”。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(title: '运行信息'),
        _SettingsGroup(
          children: [
            ListTile(
                title: const Text('当前状态'), subtitle: SelectableText(_status)),
            ListTile(
                title: const Text('IMAP 最近检查'),
                subtitle: SelectableText(_lastScan)),
            ListTile(
                title: const Text('最近邮件'), subtitle: SelectableText(_lastMail)),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }
}
