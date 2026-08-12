import 'package:codex_notif/background/strong_alert_coordinator.dart';
import 'package:codex_notif/models/strong_alert.dart';
import 'package:flutter_test/flutter_test.dart';

const firstAlert = StrongAlert(
  notificationId: 48202,
  sender: 'first@example.test',
  subject: 'First',
  matchedRule: 'first rule',
  soundUri: 'content://sound/first',
);
const latestAlert = StrongAlert(
  notificationId: 48202,
  sender: 'latest@example.test',
  subject: 'Latest',
  matchedRule: 'latest rule',
  soundUri: 'content://sound/latest',
);

StrongAlertCoordinator testCoordinator(
  List<String> events, {
  bool failAudio = false,
  bool failNotification = false,
}) =>
    StrongAlertCoordinator(
      startAudio: (uri) async {
        events.add('start:$uri');
        if (failAudio) throw StateError('audio failed');
      },
      stopAudio: () async => events.add('stop'),
      showNotification: (alert, {required isUpdate}) async {
        if (failNotification) throw StateError('notification failed');
        events.add('notify:${alert.count}:$isUpdate');
      },
      requestFullScreen: (payload) async {
        events.add('fullscreen');
        return true;
      },
      cancelNotification: (id) async => events.add('cancel:$id'),
      publish: (alert) => events.add('publish:${alert.count}'),
      publishAcknowledged: (id) => events.add('ack:$id'),
    );

void main() {
  test('first alert starts once and later alerts only update', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);

    await coordinator.add(firstAlert);
    await coordinator.add(latestAlert);

    expect(events, [
      'start:content://sound/first',
      'notify:1:false',
      'fullscreen',
      'publish:1',
      'notify:2:true',
      'publish:2',
    ]);
  });

  test('acknowledge stops cancels clears and is idempotent', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);
    await coordinator.add(firstAlert);
    events.clear();

    await coordinator.acknowledge(notificationId: 48202);
    await coordinator.acknowledge(notificationId: 48202);

    expect(coordinator.activeAlert, isNull);
    expect(events, ['stop', 'cancel:48202', 'ack:48202']);
  });

  test('notification failure stops audio and rolls session back', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, failNotification: true);
    await expectLater(coordinator.add(firstAlert), throwsStateError);
    expect(events, ['start:content://sound/first', 'stop']);
    expect(coordinator.activeAlert, isNull);
  });

  test('audio failure still leaves a visible notification', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, failAudio: true);
    await coordinator.add(firstAlert);
    expect(events, [
      'start:content://sound/first',
      'notify:1:false',
      'fullscreen',
      'publish:1',
    ]);
  });

  test('dispose stops playback and removes the active notification', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);
    await coordinator.add(firstAlert);
    events.clear();
    await coordinator.dispose();
    expect(events, ['stop', 'cancel:48202', 'ack:48202']);
    expect(coordinator.activeAlert, isNull);
  });
}
