import 'dart:async';

import 'package:flutter/material.dart';

import '../models/mail_rule.dart';
import '../services/notification_service.dart';
import '../services/system_sound_service.dart';

class SoundPickerResult {
  const SoundPickerResult({
    required this.sound,
    this.systemSoundUri,
    this.systemSoundTitle,
  });

  final AlertSound sound;
  final String? systemSoundUri;
  final String? systemSoundTitle;
}

class SoundPickerPage extends StatefulWidget {
  const SoundPickerPage({
    super.key,
    required this.initialSound,
    this.initialSystemSoundUri,
    this.initialSystemSoundTitle,
  });

  final AlertSound initialSound;
  final String? initialSystemSoundUri;
  final String? initialSystemSoundTitle;

  @override
  State<SoundPickerPage> createState() => _SoundPickerPageState();
}

class _SoundPickerPageState extends State<SoundPickerPage> {
  late AlertSound _sound;
  String? _systemSoundUri;
  String? _systemSoundTitle;

  @override
  void initState() {
    super.initState();
    _sound = widget.initialSound;
    _systemSoundUri = widget.initialSystemSoundUri;
    _systemSoundTitle = widget.initialSystemSoundTitle;
  }

  @override
  void dispose() {
    unawaited(_stopPreview());
    super.dispose();
  }

  Future<void> _stopPreview() async {
    try {
      await SystemSoundService.stopPreview();
    } catch (_) {}
  }

  Future<void> _pickSystemSound() async {
    try {
      await _stopPreview();
      final picked =
          await SystemSoundService.pick(existingUri: _systemSoundUri);
      if (!mounted || picked == null) return;

      setState(() {
        _sound = AlertSound.systemLocal;
        _systemSoundUri = picked.uri;
        _systemSoundTitle = picked.title;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开系统铃声选择器失败：$error')),
      );
    }
  }

  Future<void> _preview() async {
    if (_sound == AlertSound.systemLocal &&
        (_systemSoundUri == null || _systemSoundUri!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择手机系统铃声')),
      );
      return;
    }

    if (_sound == AlertSound.systemLocal) {
      try {
        final currentUri = _systemSoundUri!;
        final persistentUri = await SystemSoundService.ensurePersistent(
          uri: currentUri,
          title: _systemSoundTitle ?? '手机本地声音',
        );
        if (mounted && persistentUri != currentUri) {
          setState(() => _systemSoundUri = persistentUri);
        }
      } catch (_) {}
    }

    await NotificationService.instance.testRuleSound(
      MailRule(
        id: 'sound_preview',
        type: RuleType.subject,
        pattern: '声音预览',
        sound: _sound,
        systemSoundUri: _systemSoundUri,
        systemSoundTitle: _systemSoundTitle,
      ),
    );
  }

  void _finish() {
    unawaited(_stopPreview());
    Navigator.of(context).pop(
      SoundPickerResult(
        sound: _sound,
        systemSoundUri:
            _sound == AlertSound.systemLocal ? _systemSoundUri : null,
        systemSoundTitle:
            _sound == AlertSound.systemLocal ? _systemSoundTitle : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('铃声'),
        actions: [
          TextButton(onPressed: _finish, child: const Text('完成')),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('系统声音'),
          _SettingsGroup(
            children: [
              ListTile(
                minVerticalPadding: 14,
                leading: const Icon(Icons.phone_android_rounded),
                title: const Text('选择手机系统铃声'),
                subtitle: Text(
                  _systemSoundUri == null
                      ? '打开手机自带的声音选择器'
                      : (_systemSoundTitle ?? '已选择手机本地声音'),
                ),
                trailing: _sound == AlertSound.systemLocal
                    ? const Icon(Icons.check, color: Colors.blue)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _pickSystemSound,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('内置铃声'),
          _SettingsGroup(
            children: [
              for (final sound in AlertSound.values)
                if (sound != AlertSound.systemLocal)
                  ListTile(
                    minVerticalPadding: 12,
                    title: Text(sound.label),
                    trailing: _sound == sound
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () => setState(() => _sound = sound),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.volume_up_rounded),
                title: const Text('试听当前声音'),
                onTap: _preview,
              ),
            ],
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
