import '../models/strong_alert.dart';
import 'strong_alert_session.dart';

int _sessionSequence = 0;

String _defaultSessionToken() =>
    '${DateTime.now().microsecondsSinceEpoch}-${++_sessionSequence}';

class StrongAlertCoordinator {
  StrongAlertCoordinator({
    String Function()? createSessionToken,
    required this.startAudio,
    required this.stopAudio,
    required this.showNotification,
    required this.requestFullScreen,
    required this.cancelNotification,
    required this.publish,
    required this.publishAcknowledged,
  }) : createSessionToken = createSessionToken ?? _defaultSessionToken;

  final String Function() createSessionToken;
  final Future<void> Function(String uri) startAudio;
  final Future<void> Function() stopAudio;
  final Future<void> Function(StrongAlert alert, {required bool isUpdate})
      showNotification;
  final Future<bool> Function(String payload) requestFullScreen;
  final Future<void> Function(int notificationId) cancelNotification;
  final void Function(StrongAlert alert) publish;
  final void Function(int notificationId, String sessionToken)
      publishAcknowledged;

  Future<void> _tail = Future<void>.value();
  StrongAlert? _activeAlert;
  _CleanupState? _pendingCleanup;
  bool _disposeRequested = false;

  StrongAlert? get activeAlert => _activeAlert;

  Future<StrongAlert> add(StrongAlert latest) {
    if (_disposeRequested) {
      return Future<StrongAlert>.error(
        StateError('强提醒协调器已销毁。'),
      );
    }
    return _serialize(() => _add(latest));
  }

  Future<StrongAlert> _add(StrongAlert latest) async {
    await _continuePendingCleanup();
    if (_pendingCleanup != null) {
      throw StateError('上一个强提醒仍在清理，暂不能开始新会话。');
    }

    final previous = _activeAlert;
    final first = previous == null;
    final candidate =
        first ? latest.copyWith(sessionToken: createSessionToken()) : latest;
    final merged = mergeStrongAlert(previous, candidate);

    if (first) {
      try {
        await startAudio(merged.soundUri);
      } catch (_) {}
    }

    try {
      await showNotification(merged, isUpdate: !first);
    } catch (error, stackTrace) {
      if (first) {
        _activeAlert = null;
        _pendingCleanup = _CleanupState.initialFailure(merged);
        await _continuePendingCleanup();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    _activeAlert = merged;
    if (first) {
      try {
        await requestFullScreen(merged.toPayload());
      } catch (_) {}
    }
    publish(merged);
    return merged;
  }

  Future<void> acknowledge({
    int? notificationId,
    String? sessionToken,
  }) =>
      _serialize(() async {
        final token = sessionToken ?? '';
        final pending = _pendingCleanup;
        if (pending != null) {
          if (_matches(pending.alert, notificationId, token)) {
            await _continuePendingCleanup();
          }
          return;
        }

        final active = _activeAlert;
        if (active == null || !_matches(active, notificationId, token)) return;

        _activeAlert = null;
        _pendingCleanup = _CleanupState.acknowledgement(active);
        await _continuePendingCleanup();
      });

  Future<void> dispose() {
    _disposeRequested = true;
    return _serialize(() async {
      final active = _activeAlert;
      if (active != null) {
        _activeAlert = null;
        _pendingCleanup ??= _CleanupState.acknowledgement(active);
      }
      await _continuePendingCleanup();
    });
  }

  bool _matches(
    StrongAlert alert,
    int? notificationId,
    String sessionToken,
  ) =>
      sessionToken.isNotEmpty &&
      sessionToken == alert.sessionToken &&
      (notificationId == null || notificationId == alert.notificationId);

  Future<void> _continuePendingCleanup() async {
    final cleanup = _pendingCleanup;
    if (cleanup == null) return;

    if (!cleanup.audioStopped) {
      try {
        await stopAudio();
        cleanup.audioStopped = true;
      } catch (_) {}
    }

    if (!cleanup.notificationCancelled) {
      try {
        await cancelNotification(cleanup.alert.notificationId);
        cleanup.notificationCancelled = true;
      } catch (_) {}
    }

    if (!cleanup.isComplete) return;
    _pendingCleanup = null;
    if (cleanup.publishAcknowledgement) {
      publishAcknowledged(
        cleanup.alert.notificationId,
        cleanup.alert.sessionToken,
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

class _CleanupState {
  _CleanupState.initialFailure(this.alert)
      : notificationCancelled = true,
        publishAcknowledgement = false;

  _CleanupState.acknowledgement(this.alert)
      : notificationCancelled = false,
        publishAcknowledgement = true;

  final StrongAlert alert;
  final bool publishAcknowledgement;
  bool audioStopped = false;
  bool notificationCancelled;

  bool get isComplete => audioStopped && notificationCancelled;
}
