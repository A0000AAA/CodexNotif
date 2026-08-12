import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release identity and visible version are stable', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(pubspec, contains('version: 0.1.0-beta.2+2'));
    expect(gradle, contains('applicationId = "org.codexnotif.mobile"'));
    expect(
      gradle,
      contains(r'versionName = "v${flutter.versionName}"'),
    );
  });

  test('Android release build requires repository-external signing', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(gradle, isNot(contains('signingConfigs.debug')));
    expect(gradle, contains('CODEXNOTIF_ANDROID_KEYSTORE'));
    expect(gradle, contains('CODEXNOTIF_ANDROID_STORE_PASSWORD'));
    expect(gradle, contains('CODEXNOTIF_ANDROID_KEY_ALIAS'));
    expect(gradle, contains('CODEXNOTIF_ANDROID_KEY_PASSWORD'));
    expect(gradle, contains('Release signing is not configured'));
  });

  test('Android manifest removes boot and battery exemption capabilities', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final homePage = File('lib/screens/home_page.dart').readAsStringSync();

    expect(
      RegExp(
        r'<uses-permission\s+android:name="android\.permission\.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"\s+tools:node="remove"\s*/>',
        multiLine: true,
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      manifest,
      contains('android.permission.RECEIVE_BOOT_COMPLETED'),
    );
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest, contains('flutter_foreground_task.service.RebootReceiver'));
    expect(manifest, contains('flutter_foreground_task.service.RestartReceiver'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(homePage, isNot(contains('requestBatteryOptimizationExemption')));
  });

  test('foreground service stops only when Android removes the task', () {
    final foregroundService = File(
      'third_party/flutter_foreground_task/android/src/main/kotlin/'
      'com/pravera/flutter_foreground_task/service/ForegroundService.kt',
    ).readAsStringSync();
    final visibilityTracker = File(
      'third_party/flutter_foreground_task/android/src/main/kotlin/'
      'com/pravera/flutter_foreground_task/utils/TrackVisibilityUtils.kt',
    );

    expect(foregroundService, isNot(contains('TrackVisibilityUtils.install')));
    expect(foregroundService, contains('override fun onTaskRemoved'));
    expect(
      RegExp(
        r'override fun onTaskRemoved[\s\S]*?isSetStopWithTaskFlag[\s\S]*?stopSelf\(\)',
      ).hasMatch(foregroundService),
      isTrue,
    );
    expect(visibilityTracker.existsSync(), isFalse);
  });
}
