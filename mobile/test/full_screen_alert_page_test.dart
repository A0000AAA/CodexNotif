import 'dart:io';

import 'package:codex_notif/models/strong_alert.dart';
import 'package:codex_notif/screens/full_screen_alert_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const firstAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'first@example.test',
    subject: 'First',
    matchedRule: 'subject',
  );
  const updatedAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'latest@example.test',
    subject: 'Latest',
    matchedRule: 'subject',
    count: 2,
  );

  testWidgets('page updates in place and acknowledgement is its only exit',
      (tester) async {
    final alert = ValueNotifier(firstAlert);
    var acknowledged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenAlertPage(
          alertListenable: alert,
          onAcknowledge: () async => acknowledged = true,
        ),
      ),
    );

    expect(find.text('First'), findsOneWidget);
    alert.value = updatedAlert;
    await tester.pump();

    expect(find.text('收到多封匹配邮件'), findsOneWidget);
    expect(find.text('共 2 封'), findsOneWidget);
    expect(find.text('latest@example.test'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is FilledButton),
        findsOneWidget);

    await tester.tap(find.text('我知道了，停止响铃'));
    await tester.pump();

    expect(acknowledged, isTrue);
  });

  test('page never owns strong-alert playback', () {
    final source =
        File('lib/screens/full_screen_alert_page.dart').readAsStringSync();

    expect(source, isNot(contains('SystemSoundService.startAlert')));
    expect(source, isNot(contains('SystemSoundService.stopAlert')));
    expect(source, isNot(contains('onStartPlayback')));
    expect(source, isNot(contains('onStopPlayback')));
  });
}
