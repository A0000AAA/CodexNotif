import 'dart:async';

import 'package:flutter/material.dart';

import '../models/mail_rule.dart';
import '../services/notification_service.dart';
import '../services/system_sound_service.dart';
import 'sound_picker_page.dart';

class RuleEditorOutcome {
  const RuleEditorOutcome._({this.rule, this.isDeleted = false});

  factory RuleEditorOutcome.saved(MailRule rule) =>
      RuleEditorOutcome._(rule: rule);

  factory RuleEditorOutcome.deleted() =>
      const RuleEditorOutcome._(isDeleted: true);

  final MailRule? rule;
  final bool isDeleted;
}

class RuleEditorPage extends StatefulWidget {
  const RuleEditorPage({super.key, this.initial});

  final MailRule? initial;

  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
  late final TextEditingController _patternController;
  late RuleType _type;
  late AlertMode _alertMode;
  late AlertSound _sound;
  late bool _enabled;
  String? _systemSoundUri;
  String? _systemSoundTitle;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _patternController = TextEditingController(text: initial?.pattern ?? '');
    _type = initial?.type ?? RuleType.subject;
    _alertMode = initial?.alertMode ?? AlertMode.normal;
    _sound = initial?.sound ?? AlertSound.alert;
    _enabled = initial?.enabled ?? true;
    _systemSoundUri = initial?.systemSoundUri;
    _systemSoundTitle = initial?.systemSoundTitle;
  }

  @override
  void dispose() {
    unawaited(_stopPreview());
    _patternController.dispose();
    super.dispose();
  }

  Future<void> _stopPreview() async {
    try {
      await SystemSoundService.stopPreview();
    } catch (_) {}
  }

  MailRule _buildRule() {
    return MailRule(
      id: widget.initial?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      pattern: _patternController.text.trim(),
      sound: _sound,
      alertMode: _alertMode,
      enabled: _enabled,
      systemSoundUri: _sound == AlertSound.systemLocal ? _systemSoundUri : null,
      systemSoundTitle:
          _sound == AlertSound.systemLocal ? _systemSoundTitle : null,
    );
  }

  bool _validate(MailRule rule) {
    if (rule.pattern.isEmpty) {
      _showMessage('匹配文字不能为空');
      return false;
    }
    if (rule.sound == AlertSound.systemLocal &&
        (rule.systemSoundUri == null || rule.systemSoundUri!.isEmpty)) {
      _showMessage('请先选择手机系统铃声');
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
    await _ensurePersistentSystemSound();
    if (!mounted) return;
    final rule = _buildRule();
    if (!_validate(rule)) return;
    Navigator.of(context).pop(RuleEditorOutcome.saved(rule));
  }

  Future<void> _openSoundPicker() async {
    await _stopPreview();
    if (!mounted) return;
    final result = await Navigator.of(context).push<SoundPickerResult>(
      MaterialPageRoute(
        builder: (_) => SoundPickerPage(
          initialSound: _sound,
          initialSystemSoundUri: _systemSoundUri,
          initialSystemSoundTitle: _systemSoundTitle,
        ),
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      _sound = result.sound;
      _systemSoundUri = result.systemSoundUri;
      _systemSoundTitle = result.systemSoundTitle;
    });
  }

  Future<void> _preview() async {
    await _ensurePersistentSystemSound();
    if (!mounted) return;
    final rule = _buildRule();
    if (!_validate(rule)) return;
    await NotificationService.instance.testRuleSound(rule);
  }

  Future<void> _ensurePersistentSystemSound() async {
    final uri = _systemSoundUri;
    if (_sound != AlertSound.systemLocal || uri == null || uri.isEmpty) return;

    try {
      final persistentUri = await SystemSoundService.ensurePersistent(
        uri: uri,
        title: _systemSoundTitle ?? '手机本地声音',
      );
      if (mounted && persistentUri != uri) {
        setState(() => _systemSoundUri = persistentUri);
      }
    } catch (_) {
      // The notification layer will fall back to the original URI. A fresh
      // picker selection will persist a MediaStore copy on supported devices.
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除这条规则？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    Navigator.of(context).pop(RuleEditorOutcome.deleted());
  }

  String get _soundTitle {
    if (_sound == AlertSound.systemLocal) {
      return _systemSoundTitle ?? '尚未选择手机系统铃声';
    }
    return _sound.label;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '添加提醒规则' : '编辑提醒规则'),
        actions: [
          TextButton(onPressed: _save, child: const Text('完成')),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const _SectionTitle('匹配条件'),
          _SettingsGroup(
            children: [
              ListTile(
                title: const Text('匹配范围'),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<RuleType>(
                    value: _type,
                    items: [
                      for (final type in RuleType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _patternController,
                  decoration: InputDecoration(
                    labelText:
                        _type == RuleType.subject ? '主题包含文字' : '发件人或联系人包含文字',
                    hintText: _type == RuleType.subject
                        ? '例如：Codex 任务已完成'
                        : '例如：codex_notif',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('通知方式'),
          _SettingsGroup(
            children: [
              for (final mode in AlertMode.values)
                ListTile(
                  minVerticalPadding: 14,
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                  trailing: _alertMode == mode ? const Icon(Icons.check) : null,
                  onTap: () => setState(() => _alertMode = mode),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('声音'),
          _SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('铃声'),
                subtitle: Text(_soundTitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openSoundPicker,
              ),
              ListTile(
                leading: const Icon(Icons.volume_up_rounded),
                title: const Text('试听当前声音'),
                onTap: _preview,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsGroup(
            children: [
              SwitchListTile(
                title: const Text('启用这条规则'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
          if (widget.initial != null) ...[
            const SizedBox(height: 24),
            _SettingsGroup(
              children: [
                ListTile(
                  title: Text(
                    '删除规则',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: _delete,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '规则按列表从上到下匹配，第一条命中规则决定通知方式和铃声。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
