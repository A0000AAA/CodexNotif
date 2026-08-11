import 'dart:io';

import 'package:codex_notif/models/mail_rule.dart';
import 'package:codex_notif/services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bundled sound has a packaged Android raw resource', () {
    for (final sound in AlertSound.values) {
      final rawName = sound.rawName;
      if (rawName == null) continue;
      final file = File('android/app/src/main/res/raw/$rawName.wav');
      expect(file.existsSync(), isTrue, reason: '$rawName.wav is missing');
      expect(file.lengthSync(), greaterThan(0));
    }
    final selectedRingtone =
        File('android/app/src/main/res/raw/tone_hajimi.wav');
    expect(selectedRingtone.existsSync(), isTrue);
    expect(selectedRingtone.lengthSync(), greaterThan(0));
  });

  test('strong alerts share one call-like notification slot', () {
    expect(
      notificationIdForAlert(AlertMode.strong, timestampMillis: 100),
      notificationIdForAlert(AlertMode.strong, timestampMillis: 200),
    );
    expect(
      notificationIdForAlert(AlertMode.normal, timestampMillis: 100),
      isNot(notificationIdForAlert(
        AlertMode.normal,
        timestampMillis: 200,
      )),
    );
  });

  test('strong details remain ongoing and insistent until acknowledgement', () {
    final details = buildAndroidNotificationDetails(
      mode: AlertMode.strong,
      channelId: 'strong',
      channelName: 'Strong',
      sound: const RawResourceAndroidNotificationSound('tone_phone'),
      sender: 'bot@example.com',
      subject: 'Done',
      matchedRule: 'subject: Done',
    );

    expect(details.ongoing, isTrue);
    expect(details.autoCancel, isFalse);
    expect(details.fullScreenIntent, isTrue);
    expect(details.category, AndroidNotificationCategory.alarm);
    expect(details.audioAttributesUsage, AudioAttributesUsage.alarm);
    expect(details.additionalFlags, contains(4));
    expect(details.actions, hasLength(1));
    expect(details.actions!.single.id, 'acknowledge');
    expect(details.actions!.single.cancelNotification, isTrue);
  });

  test('normal details preserve one-shot message behavior', () {
    final details = buildAndroidNotificationDetails(
      mode: AlertMode.normal,
      channelId: 'normal',
      channelName: 'Normal',
      sound: const RawResourceAndroidNotificationSound('tone_alert'),
      sender: 'bot@example.com',
      subject: 'Done',
      matchedRule: 'subject: Done',
    );

    expect(details.ongoing, isFalse);
    expect(details.autoCancel, isTrue);
    expect(details.fullScreenIntent, isFalse);
    expect(details.category, AndroidNotificationCategory.message);
    expect(details.audioAttributesUsage, AudioAttributesUsage.notification);
    expect(details.additionalFlags, isNull);
    expect(details.actions, isNull);
  });

  test('preview uses alarm audio without becoming a full-screen alert', () {
    final details = buildAndroidNotificationDetails(
      mode: AlertMode.normal,
      channelId: 'preview',
      channelName: 'Preview',
      sound: const RawResourceAndroidNotificationSound('tone_phone'),
      sender: 'preview',
      subject: 'preview',
      matchedRule: 'preview',
      forceAlarmAudio: true,
    );

    expect(details.audioAttributesUsage, AudioAttributesUsage.alarm);
    expect(details.fullScreenIntent, isFalse);
    expect(details.ongoing, isFalse);
  });
}
