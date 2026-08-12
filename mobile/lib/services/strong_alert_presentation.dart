import 'package:flutter/foundation.dart';

import '../models/strong_alert.dart';

class StrongAlertPresentationUpdate {
  const StrongAlertPresentationUpdate(this.listenable, this.created);

  final ValueNotifier<StrongAlert> listenable;
  final bool created;
}

class StrongAlertPresentation {
  final Map<String, ValueNotifier<StrongAlert>> _alerts = {};

  StrongAlertPresentationUpdate openOrUpdate(StrongAlert alert) {
    final existing = _alerts[alert.sessionToken];
    if (existing != null) {
      existing.value = alert;
      return StrongAlertPresentationUpdate(existing, false);
    }

    final created = ValueNotifier(alert);
    _alerts[alert.sessionToken] = created;
    return StrongAlertPresentationUpdate(created, true);
  }

  ValueNotifier<StrongAlert>? remove(
    String sessionToken, {
    ValueNotifier<StrongAlert>? expected,
  }) {
    final existing = _alerts[sessionToken];
    if (existing == null ||
        expected != null && !identical(existing, expected)) {
      return null;
    }
    return _alerts.remove(sessionToken);
  }
}
