import 'dart:async';

import 'package:codex_notif/main.dart';
import 'package:codex_notif/models/strong_alert.dart';
import 'package:codex_notif/screens/full_screen_alert_page.dart';
import 'package:codex_notif/services/native_alert_launch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.codexnotif.mobile/alert_launch');
  late StreamController<StrongAlert> notificationAlerts;

  const first = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'first@example.test',
    subject: 'First',
    matchedRule: 'subject',
  );
  const updated = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'updated@example.test',
    subject: 'Updated',
    matchedRule: 'subject',
    count: 3,
  );
  const next = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-next',
    sender: 'next@example.test',
    subject: 'Next session',
    matchedRule: 'subject',
  );

  setUp(() async {
    FlutterForegroundTask.dataCallbacks.clear();
    notificationAlerts = StreamController<StrongAlert>.broadcast();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await NativeAlertLaunchService.instance.initialize();
    NativeAlertLaunchService.instance.takePending();
  });

  tearDown(() async {
    FlutterForegroundTask.dataCallbacks.clear();
    await notificationAlerts.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('notification native and task delivery share one token route',
      (tester) async {
    await tester.pumpWidget(
      QqMailPagerApp(
        notificationAlerts: notificationAlerts.stream,
        home: const Scaffold(body: Text('home')),
      ),
    );

    notificationAlerts.add(first);
    await tester.pumpAndSettle();
    await _pushNative(updated);
    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlert',
      'payload': updated.toPayload(),
    });
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenAlertPage), findsOneWidget);
    expect(find.text('共 3 封'), findsOneWidget);
    expect(find.text('updated@example.test'), findsOneWidget);
  });

  testWidgets('acknowledgement before the first frame prevents route push',
      (tester) async {
    await tester.pumpWidget(
      QqMailPagerApp(
        notificationAlerts: notificationAlerts.stream,
        home: const Scaffold(body: Text('home')),
      ),
    );

    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlert',
      'payload': first.toPayload(),
    });
    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlertAcknowledged',
      'notificationId': first.notificationId,
      'sessionToken': first.sessionToken,
    });
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenAlertPage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('wrong notification id cannot tombstone a token before push',
      (tester) async {
    await tester.pumpWidget(
      QqMailPagerApp(
        notificationAlerts: notificationAlerts.stream,
        home: const Scaffold(body: Text('home')),
      ),
    );

    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlert',
      'payload': first.toPayload(),
    });
    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlertAcknowledged',
      'notificationId': 999,
      'sessionToken': first.sessionToken,
    });
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenAlertPage), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('old acknowledgement cannot close a newer token route',
      (tester) async {
    await tester.pumpWidget(
      QqMailPagerApp(
        notificationAlerts: notificationAlerts.stream,
        home: const Scaffold(body: Text('home')),
      ),
    );

    notificationAlerts.add(first);
    await tester.pumpAndSettle();
    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlert',
      'payload': next.toPayload(),
    });
    await tester.pumpAndSettle();

    FlutterForegroundTask.dataCallbacks.single({
      'type': 'strongAlertAcknowledged',
      'notificationId': first.notificationId,
      'sessionToken': first.sessionToken,
    });
    await tester.pumpAndSettle();
    await _pushNative(first);
    await tester.pumpAndSettle();

    expect(
      find.byType(FullScreenAlertPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Next session'), findsOneWidget);
  });
}

Future<void> _pushNative(StrongAlert alert) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'org.codexnotif.mobile/alert_launch',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('showStrongAlert', alert.toPayload()),
    ),
    (_) {},
  );
}
