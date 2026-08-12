import 'dart:io';

import 'package:codex_notif/models/strong_alert.dart';
import 'package:codex_notif/services/native_alert_launch_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.codexnotif.mobile/alert_launch');
  const firstAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'first@example.test',
    subject: 'First',
    matchedRule: 'subject',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native launch payload is retained exactly once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'drainPendingStrongAlertAndMarkReady'
          ? firstAlert.toPayload()
          : null,
    );
    final service = NativeAlertLaunchService();

    await service.initialize();

    expect(service.takePending(), firstAlert);
    expect(service.takePending(), isNull);
  });

  test('native push publishes the payload with its session token', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final service = NativeAlertLaunchService();
    await service.initialize();
    final next = service.alerts.first;

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('showStrongAlert', firstAlert.toPayload()),
      ),
      (_) {},
    );

    expect(await next, firstAlert);
    expect(service.takePending(), isNull);
  });

  test('cold pending followed during drain retains only the latest payload',
      () async {
    const latestAlert = StrongAlert(
      notificationId: 48202,
      sessionToken: 'session-first',
      sender: 'latest@example.test',
      subject: 'Latest',
      matchedRule: 'subject',
      count: 2,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'drainPendingStrongAlertAndMarkReady') return null;
      await _pushNative(latestAlert);
      return firstAlert.toPayload();
    });
    final service = NativeAlertLaunchService();

    await service.initialize();

    expect(service.takePending(), latestAlert);
    expect(service.takePending(), isNull);
  });

  test('MainActivity consumes the launch extra and has no alert player', () {
    final source = File(
      'android/app/src/main/java/org/codexnotif/mobile/MainActivity.java',
    ).readAsStringSync();

    expect(source, isNot(contains('"takePendingStrongAlert".equals')));
    expect(source, contains('drainPendingStrongAlertAndMarkReady'));
    expect(source, contains('dartAlertLaunchReady'));
    expect(source, contains('showStrongAlert'));
    expect(
      source,
      contains('org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD'),
    );
    expect(source, isNot(contains('alertPlayer')));
    expect(source, isNot(contains('"startAlertSound"')));
    expect(source, isNot(contains('"stopAlertSound"')));
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
