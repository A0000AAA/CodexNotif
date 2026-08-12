import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class StrongAlertPlatformService {
  static const _channel =
      MethodChannel('org.codexnotif.mobile/background_audio');

  static Future<void> startAudio(String soundUri) =>
      _channel.invokeMethod<void>('startAlertSound', {'uri': soundUri});

  static Future<void> stopAudio() =>
      _channel.invokeMethod<void>('stopAlertSound');

  static Future<bool> requestFullScreen(String payload) async =>
      await _channel.invokeMethod<bool>(
        'showFullScreenAlert',
        {'payload': payload},
      ) ??
      false;

  static Future<void> acknowledge(
    int notificationId, {
    required String sessionToken,
  }) async {
    FlutterForegroundTask.sendDataToTask({
      'command': 'acknowledgeStrongAlert',
      'notificationId': notificationId,
      'sessionToken': sessionToken,
    });
  }
}
