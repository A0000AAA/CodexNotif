import '../models/strong_alert.dart';
import 'strong_alert_session.dart';

class StrongAlertCoordinator {
  StrongAlertCoordinator({
    required this.startAudio,
    required this.stopAudio,
    required this.showNotification,
    required this.requestFullScreen,
    required this.cancelNotification,
    required this.publish,
    required this.publishAcknowledged,
  });

  final Future<void> Function(String uri) startAudio;
  final Future<void> Function() stopAudio;
  final Future<void> Function(StrongAlert alert, {required bool isUpdate})
      showNotification;
  final Future<bool> Function(String payload) requestFullScreen;
  final Future<void> Function(int notificationId) cancelNotification;
  final void Function(StrongAlert alert) publish;
  final void Function(int notificationId) publishAcknowledged;

  StrongAlert? _activeAlert;
  int? _lastAcknowledgedId;

  StrongAlert? get activeAlert => _activeAlert;

  Future<StrongAlert> add(StrongAlert latest) async {
    final first = _activeAlert == null;
    final merged = mergeStrongAlert(_activeAlert, latest);
    if (first) {
      try {
        await startAudio(merged.soundUri);
      } catch (_) {}
    }
    try {
      await showNotification(merged, isUpdate: !first);
    } catch (_) {
      if (first) await _stopIgnoringErrors();
      _activeAlert = null;
      rethrow;
    }
    _activeAlert = merged;
    _lastAcknowledgedId = null;
    if (first) {
      try {
        await requestFullScreen(merged.toPayload());
      } catch (_) {}
    }
    publish(merged);
    return merged;
  }

  Future<void> acknowledge({int? notificationId}) async {
    final id = _activeAlert?.notificationId ?? notificationId;
    if (id == null || _lastAcknowledgedId == id) return;
    _activeAlert = null;
    _lastAcknowledgedId = id;
    await _stopIgnoringErrors();
    try {
      await cancelNotification(id);
    } catch (_) {}
    publishAcknowledged(id);
  }

  Future<void> dispose() async {
    final id = _activeAlert?.notificationId;
    _activeAlert = null;
    await _stopIgnoringErrors();
    if (id != null && _lastAcknowledgedId != id) {
      _lastAcknowledgedId = id;
      try {
        await cancelNotification(id);
      } catch (_) {}
      publishAcknowledged(id);
    }
  }

  Future<void> _stopIgnoringErrors() async {
    try {
      await stopAudio();
    } catch (_) {}
  }
}
