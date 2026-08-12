import 'package:codex_notif/services/strong_alert_platform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.codexnotif.mobile/background_audio');
  const foregroundTaskChannel =
      MethodChannel('flutter_foreground_task/methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(foregroundTaskChannel, null);
  });

  test('platform service uses background engine channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'showFullScreenAlert';
    });

    await StrongAlertPlatformService.startAudio('content://sound/selected');
    expect(
      await StrongAlertPlatformService.requestFullScreen(
        '{"type":"strongAlert"}',
      ),
      isTrue,
    );
    await StrongAlertPlatformService.stopAudio();

    expect(calls.map((call) => call.method), [
      'startAlertSound',
      'showFullScreenAlert',
      'stopAlertSound',
    ]);
  });

  test('acknowledgement forwards the matching session token to the task',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(foregroundTaskChannel, (call) async {
      calls.add(call);
      return null;
    });

    await StrongAlertPlatformService.acknowledge(
      48202,
      sessionToken: 'session-7',
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'sendData');
    expect(calls.single.arguments, {
      'command': 'acknowledgeStrongAlert',
      'notificationId': 48202,
      'sessionToken': 'session-7',
    });
  });
}
