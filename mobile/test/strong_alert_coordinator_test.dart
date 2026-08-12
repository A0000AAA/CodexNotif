import 'dart:async';

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
  int stopFailures = 0,
  int cancelFailures = 0,
  Future<void> Function(StrongAlert alert, bool isUpdate)?
      showNotificationOverride,
}) {
  var session = 0;
  return StrongAlertCoordinator(
    createSessionToken: () => 'session-${++session}',
    startAudio: (uri) async {
      events.add('start:$uri');
      if (failAudio) throw StateError('audio failed');
    },
    stopAudio: () async {
      events.add('stop');
      if (stopFailures > 0) {
        stopFailures--;
        throw StateError('stop failed');
      }
    },
    showNotification: (alert, {required isUpdate}) async {
      events.add('notify:${alert.count}:$isUpdate:${alert.sessionToken}');
      if (showNotificationOverride != null) {
        await showNotificationOverride(alert, isUpdate);
      }
      if (failNotification) throw StateError('notification failed');
    },
    requestFullScreen: (payload) async {
      events.add('fullscreen');
      return true;
    },
    cancelNotification: (id) async {
      events.add('cancel:$id');
      if (cancelFailures > 0) {
        cancelFailures--;
        throw StateError('cancel failed');
      }
    },
    publish: (alert) =>
        events.add('publish:${alert.count}:${alert.sessionToken}'),
    publishAcknowledged: (id, sessionToken) =>
        events.add('ack:$id:$sessionToken'),
  );
}

void main() {
  test('first alert starts once and later alerts only update', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);

    final first = await coordinator.add(firstAlert);
    final latest = await coordinator.add(latestAlert);

    expect(first.sessionToken, 'session-1');
    expect(latest.sessionToken, 'session-1');
    expect(events, [
      'start:content://sound/first',
      'notify:1:false:session-1',
      'fullscreen',
      'publish:1:session-1',
      'notify:2:true:session-1',
      'publish:2:session-1',
    ]);
  });

  test('overlapping adds are serialized behind the first notification',
      () async {
    final events = <String>[];
    final entered = Completer<void>();
    final release = Completer<void>();
    final coordinator = testCoordinator(
      events,
      showNotificationOverride: (alert, isUpdate) async {
        if (alert.count == 1) {
          entered.complete();
          await release.future;
        }
      },
    );

    final first = coordinator.add(firstAlert);
    await entered.future;
    final second = coordinator.add(latestAlert);
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      'start:content://sound/first',
      'notify:1:false:session-1',
    ]);

    release.complete();
    await Future.wait([first, second]);
    expect(
      events.where((event) => event.startsWith('start:')),
      hasLength(1),
    );
    expect(
      events.where((event) => event == 'fullscreen'),
      hasLength(1),
    );
    expect(coordinator.activeAlert?.count, 2);
  });

  test('overlapping update acknowledge and dispose finish in queue order',
      () async {
    final events = <String>[];
    final entered = Completer<void>();
    final release = Completer<void>();
    final coordinator = testCoordinator(
      events,
      showNotificationOverride: (alert, isUpdate) async {
        if (alert.count == 2) {
          entered.complete();
          await release.future;
        }
      },
    );
    final first = await coordinator.add(firstAlert);
    events.clear();

    final update = coordinator.add(latestAlert);
    await entered.future;
    final acknowledge = coordinator.acknowledge(
      notificationId: 48202,
      sessionToken: first.sessionToken,
    );
    final dispose = coordinator.dispose();
    release.complete();

    await Future.wait([update, acknowledge, dispose]);
    expect(coordinator.activeAlert, isNull);
    expect(events, [
      'notify:2:true:session-1',
      'publish:2:session-1',
      'stop',
      'cancel:48202',
      'ack:48202:session-1',
    ]);
  });

  test('acknowledge stops cancels clears and is idempotent', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);
    final alert = await coordinator.add(firstAlert);
    events.clear();

    await coordinator.acknowledge(
      notificationId: 48202,
      sessionToken: alert.sessionToken,
    );
    await coordinator.acknowledge(
      notificationId: 48202,
      sessionToken: alert.sessionToken,
    );

    expect(coordinator.activeAlert, isNull);
    expect(events, ['stop', 'cancel:48202', 'ack:48202:session-1']);
  });

  test('stale token cannot acknowledge a newer fixed-id session', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);
    final old = await coordinator.add(firstAlert);
    await coordinator.acknowledge(
      notificationId: old.notificationId,
      sessionToken: old.sessionToken,
    );
    final current = await coordinator.add(latestAlert);
    events.clear();

    await coordinator.acknowledge(
      notificationId: old.notificationId,
      sessionToken: old.sessionToken,
    );

    expect(current.sessionToken, 'session-2');
    expect(coordinator.activeAlert, current);
    expect(events, isEmpty);
  });

  test('initial notification failure rolls session back and propagates',
      () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, failNotification: true);
    await expectLater(coordinator.add(firstAlert), throwsStateError);
    expect(events, [
      'start:content://sound/first',
      'notify:1:false:session-1',
      'stop',
    ]);
    expect(coordinator.activeAlert, isNull);
  });

  test('update notification failure restores the previous active session',
      () async {
    final events = <String>[];
    final coordinator = testCoordinator(
      events,
      showNotificationOverride: (alert, isUpdate) async {
        if (isUpdate) throw StateError('update failed');
      },
    );
    final first = await coordinator.add(firstAlert);
    events.clear();

    await expectLater(coordinator.add(latestAlert), throwsStateError);

    expect(coordinator.activeAlert, first);
    expect(events, ['notify:2:true:session-1']);
  });

  test('audio failure still leaves a visible notification', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, failAudio: true);
    await coordinator.add(firstAlert);
    expect(events, [
      'start:content://sound/first',
      'notify:1:false:session-1',
      'fullscreen',
      'publish:1:session-1',
    ]);
  });

  test('stop failure is retried without repeating successful cancellation',
      () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, stopFailures: 1);
    final alert = await coordinator.add(firstAlert);
    events.clear();

    await coordinator.acknowledge(
      notificationId: alert.notificationId,
      sessionToken: alert.sessionToken,
    );
    expect(events, ['stop', 'cancel:48202']);

    await coordinator.acknowledge(
      notificationId: alert.notificationId,
      sessionToken: alert.sessionToken,
    );
    expect(events, [
      'stop',
      'cancel:48202',
      'stop',
      'ack:48202:session-1',
    ]);
  });

  test('cancel failure is retried without repeating successful stop', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, cancelFailures: 1);
    final alert = await coordinator.add(firstAlert);
    events.clear();

    await coordinator.acknowledge(
      notificationId: alert.notificationId,
      sessionToken: alert.sessionToken,
    );
    expect(events, ['stop', 'cancel:48202']);

    await coordinator.acknowledge(
      notificationId: alert.notificationId,
      sessionToken: alert.sessionToken,
    );
    expect(events, [
      'stop',
      'cancel:48202',
      'cancel:48202',
      'ack:48202:session-1',
    ]);
  });

  test('unfinished cleanup prevents a later add from starting', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events, stopFailures: 2);
    final alert = await coordinator.add(firstAlert);
    await coordinator.acknowledge(
      notificationId: alert.notificationId,
      sessionToken: alert.sessionToken,
    );
    events.clear();

    await expectLater(coordinator.add(latestAlert), throwsStateError);

    expect(events, ['stop']);
    expect(coordinator.activeAlert, isNull);
  });

  test('dispose stops playback and removes the active notification', () async {
    final events = <String>[];
    final coordinator = testCoordinator(events);
    await coordinator.add(firstAlert);
    events.clear();
    await coordinator.dispose();
    await coordinator.dispose();
    expect(events, ['stop', 'cancel:48202', 'ack:48202:session-1']);
    expect(coordinator.activeAlert, isNull);
  });
}
