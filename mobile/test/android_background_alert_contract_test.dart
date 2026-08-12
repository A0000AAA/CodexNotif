import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native service cleans audio without logging selected URIs', () {
    final root = 'third_party/flutter_foreground_task/android/src/main/kotlin/'
        'com/pravera/flutter_foreground_task';
    final service =
        File('$root/service/ForegroundService.kt').readAsStringSync();
    final player = File('$root/service/AlertSoundPlayer.kt').readAsStringSync();
    final plugin =
        File('$root/FlutterForegroundTaskPlugin.kt').readAsStringSync();

    expect(service, contains('AlertSoundPlayer.stop()'));
    expect(player, isNot(contains(r'uri=$candidate')));
    expect(plugin, contains('"showFullScreenAlert"'));
  });
}
