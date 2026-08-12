import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/strong_alert.dart';
import '../services/notification_service.dart';
import '../services/strong_alert_platform_service.dart';

class FullScreenAlertPage extends StatefulWidget {
  const FullScreenAlertPage({
    super.key,
    required this.alertListenable,
    this.onAcknowledge,
  });

  final ValueListenable<StrongAlert> alertListenable;
  final Future<void> Function()? onAcknowledge;

  @override
  State<FullScreenAlertPage> createState() => _FullScreenAlertPageState();
}

class _FullScreenAlertPageState extends State<FullScreenAlertPage> {
  bool _acknowledging = false;

  Future<void> _acknowledge() async {
    if (_acknowledging) return;
    setState(() => _acknowledging = true);

    final callback = widget.onAcknowledge;
    if (callback != null) {
      await callback();
    } else {
      final alert = widget.alertListenable.value;
      await StrongAlertPlatformService.acknowledge(
        alert.notificationId,
        sessionToken: alert.sessionToken,
      );
      await NotificationService.instance.cancel(alert.notificationId);
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StrongAlert>(
      valueListenable: widget.alertListenable,
      builder: (context, alert, _) => _buildAlert(context, alert),
    );
  }

  Widget _buildAlert(BuildContext context, StrongAlert alert) {
    final colors = Theme.of(context).colorScheme;
    final combined = alert.count > 1;

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
                combined
                    ? '收到多封匹配邮件'
                    : alert.subject.isEmpty
                        ? '收到匹配邮件'
                        : alert.subject,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (combined) ...[
                const SizedBox(height: 8),
                Text(
                  '共 ${alert.count} 封',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                alert.sender.isEmpty ? 'QQ 邮箱规则匹配' : alert.sender,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              if (alert.matchedRule.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '匹配规则：${alert.matchedRule}',
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
