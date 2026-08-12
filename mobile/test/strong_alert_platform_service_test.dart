import 'package:codex_notif/services/strong_alert_platform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.codexnotif.mobile/background_audio');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
}
