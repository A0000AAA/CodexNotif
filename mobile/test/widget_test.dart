import 'package:codex_notif/models/app_config.dart';
import 'package:codex_notif/models/mail_rule.dart';
import 'package:codex_notif/models/monitor_health.dart';
import 'package:codex_notif/screens/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enabled monitoring is recovered when the service is absent', () {
    expect(
      shouldRecoverMonitoring(
        const AppConfig(monitoringEnabled: true),
        serviceRunning: false,
      ),
      isTrue,
    );
    expect(
      shouldRecoverMonitoring(
        const AppConfig(monitoringEnabled: true),
        serviceRunning: true,
      ),
      isFalse,
    );
  });

  testWidgets('home separates reminders from settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialConfig: const AppConfig(
            monitoringEnabled: true,
            rules: [
              MailRule(
                id: '1',
                type: RuleType.subject,
                pattern: 'Codex 任务已完成',
                sound: AlertSound.systemLocal,
                systemSoundUri: 'content://ringtone/1',
                systemSoundTitle: '哈基米系统闹铃',
                alertMode: AlertMode.strong,
              ),
            ],
          ),
          initialServiceRunning: true,
          initialMonitorHealth: MonitorHealth(
            lastScanAt: DateTime.now(),
            lastScanText: '刚刚 · 没有新邮件',
          ),
        ),
      ),
    );

    expect(find.text('后台监听中'), findsOneWidget);
    expect(find.textContaining('强提醒 · 哈基米系统闹铃'), findsOneWidget);
    expect(find.text('QQ 邮箱账户'), findsNothing);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    expect(find.text('QQ 邮箱账户'), findsOneWidget);
    expect(find.text('提醒规则'), findsNothing);
  });

  testWidgets('home warns when the service exists but scan heartbeat is stale',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialConfig: const AppConfig(monitoringEnabled: true),
          initialServiceRunning: true,
          initialMonitorHealth: MonitorHealth(
            lastScanAt: DateTime.now().subtract(const Duration(minutes: 2)),
            lastScanText: '两分钟前 · 没有新邮件',
          ),
        ),
      ),
    );

    expect(find.text('后台监听需检查'), findsOneWidget);
    expect(find.textContaining('IMAP 检查已超过 90 秒'), findsOneWidget);
    expect(find.text('两分钟前 · 没有新邮件'), findsOneWidget);
  });
}
