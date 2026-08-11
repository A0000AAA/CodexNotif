import 'package:codex_notif/models/strong_alert.dart';
import 'package:codex_notif/screens/full_screen_alert_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('acknowledgement is the only exit and invokes cancellation',
      (tester) async {
    var acknowledged = false;
    var playbackStarted = false;
    var playbackStopped = false;
    const alert = StrongAlert(
      notificationId: 42,
      sender: 'bot@example.com',
      subject: 'Codex 任务已完成',
      matchedRule: '主题包含：Codex',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenAlertPage(
          alert: alert,
          onStartPlayback: (_) async => playbackStarted = true,
          onStopPlayback: () async => playbackStopped = true,
          onAcknowledge: () async => acknowledged = true,
        ),
      ),
    );

    expect(find.text('Codex 任务已完成'), findsOneWidget);
    expect(find.text('强提醒 · 持续响铃'), findsOneWidget);
    expect(find.text('我知道了，停止响铃'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is FilledButton),
      findsOneWidget,
    );
    expect(playbackStarted, isTrue);

    await tester.tap(find.text('我知道了，停止响铃'));
    await tester.pump();

    expect(acknowledged, isTrue);
    expect(playbackStopped, isTrue);
  });
}
