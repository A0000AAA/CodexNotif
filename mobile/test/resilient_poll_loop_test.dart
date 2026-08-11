import 'dart:async';

import 'package:codex_notif/background/resilient_poll_loop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('periodic callbacks keep polling without overlap', () async {
    void Function()? fire;
    var calls = 0;
    var activePoll = Completer<void>();

    final loop = ResilientPollLoop(
      interval: const Duration(seconds: 30),
      onPoll: () {
        calls += 1;
        return activePoll.future;
      },
      scheduler: (_, callback) {
        fire = callback;
        return Timer.periodic(const Duration(days: 1), (_) {});
      },
    );

    loop.start();
    fire!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    fire!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1, reason: 'an unfinished poll must not overlap');

    activePoll.complete();
    await Future<void>.delayed(Duration.zero);
    activePoll = Completer<void>();

    fire!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);

    activePoll.complete();
    loop.stop();
  });

  test('a fresh loop starts polling after the previous loop stopped', () async {
    void Function()? fireOldLoop;
    void Function()? fireNewLoop;
    var calls = 0;

    final oldLoop = ResilientPollLoop(
      interval: const Duration(seconds: 30),
      onPoll: () async => calls += 1,
      scheduler: (_, callback) {
        fireOldLoop = callback;
        return Timer.periodic(const Duration(days: 1), (_) {});
      },
    );

    oldLoop.start();
    fireOldLoop!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    oldLoop.stop();
    fireOldLoop!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1, reason: 'stopped loop callbacks must be ignored');

    final newLoop = ResilientPollLoop(
      interval: const Duration(seconds: 30),
      onPoll: () async => calls += 1,
      scheduler: (_, callback) {
        fireNewLoop = callback;
        return Timer.periodic(const Duration(days: 1), (_) {});
      },
    );

    newLoop.start();
    fireNewLoop!();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2, reason: 'a restarted isolate creates a fresh poll loop');

    newLoop.stop();
  });
}
