import 'dart:async';

import 'package:flutter/material.dart';

import '../models/strong_alert.dart';
import '../services/notification_service.dart';
import '../services/system_sound_service.dart';

class FullScreenAlertPage extends StatefulWidget {
  const FullScreenAlertPage({
    super.key,
    required this.alert,
    this.onAcknowledge,
    this.onStartPlayback,
    this.onStopPlayback,
  });

  final StrongAlert alert;
  final Future<void> Function()? onAcknowledge;
  final Future<void> Function(String uri)? onStartPlayback;
  final Future<void> Function()? onStopPlayback;

  @override
  State<FullScreenAlertPage> createState() => _FullScreenAlertPageState();
}

class _FullScreenAlertPageState extends State<FullScreenAlertPage> {
  bool _acknowledging = false;

  @override
  void initState() {
    super.initState();
    final start = widget.onStartPlayback;
    unawaited(
      start != null
          ? start(widget.alert.soundUri)
          : SystemSoundService.startAlert(widget.alert.soundUri),
    );
  }

  Future<void> _stopPlayback() async {
    final stop = widget.onStopPlayback;
    if (stop != null) {
      await stop();
    } else {
      await SystemSoundService.stopAlert();
    }
  }

  Future<void> _acknowledge() async {
    if (_acknowledging) return;
    setState(() => _acknowledging = true);
    await _stopPlayback();

    final callback = widget.onAcknowledge;
    if (callback != null) {
      await callback();
    } else {
      await NotificationService.instance.cancel(widget.alert.notificationId);
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    unawaited(_stopPlayback());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: colors.onPrimaryContainer,
                  size: 48,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '强提醒 · 持续响铃',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.alert.subject.isEmpty ? '收到匹配邮件' : widget.alert.subject,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.alert.sender.isEmpty ? 'QQ 邮箱规则匹配' : widget.alert.sender,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              if (widget.alert.matchedRule.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '匹配规则：${widget.alert.matchedRule}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _acknowledging ? null : _acknowledge,
                  icon: _acknowledging
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('我知道了，停止响铃'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
