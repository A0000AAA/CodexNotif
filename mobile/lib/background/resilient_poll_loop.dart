import 'dart:async';

typedef PeriodicScheduler = Timer Function(
  Duration interval,
  void Function() callback,
);

Timer defaultPeriodicScheduler(
  Duration interval,
  void Function() callback,
) {
  return Timer.periodic(interval, (_) => callback());
}

class ResilientPollLoop {
  ResilientPollLoop({
    required this.interval,
    required this.onPoll,
    PeriodicScheduler scheduler = defaultPeriodicScheduler,
  }) : _scheduler = scheduler;

  final Duration interval;
  final Future<void> Function() onPoll;
  final PeriodicScheduler _scheduler;

  Timer? _timer;
  bool _polling = false;
  bool _stopped = true;

  void start() {
    _timer?.cancel();
    _stopped = false;
    _timer = _scheduler(interval, () {
      unawaited(pollNow());
    });
  }

  Future<void> pollNow() async {
    if (_stopped || _polling) return;

    _polling = true;
    try {
      await onPoll();
    } finally {
      _polling = false;
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
