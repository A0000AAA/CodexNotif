import 'dart:async';

import 'package:flutter/services.dart';

import '../models/strong_alert.dart';

class NativeAlertLaunchService {
  NativeAlertLaunchService();

  static final instance = NativeAlertLaunchService();
  static const _channel = MethodChannel(
    'org.codexnotif.mobile/alert_launch',
  );

  final StreamController<StrongAlert> _controller =
      StreamController<StrongAlert>.broadcast();
  StrongAlert? _pending;
  StrongAlert? _receivedDuringDrain;
  bool _draining = false;

  Stream<StrongAlert> get alerts => _controller.stream;

  Future<void> initialize() async {
    _draining = true;
    _receivedDuringDrain = null;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showStrongAlert') {
        final alert = StrongAlert.fromPayload(call.arguments?.toString());
        if (alert == null) return;
        if (_draining) {
          _receivedDuringDrain = alert;
        } else {
          _publishOrRetain(alert);
        }
      }
    });
    final pending = StrongAlert.fromPayload(
      await _channel.invokeMethod<String>(
        'drainPendingStrongAlertAndMarkReady',
      ),
    );
    _pending = pending;
    _draining = false;
    final receivedDuringDrain = _receivedDuringDrain;
    _receivedDuringDrain = null;
    if (receivedDuringDrain != null) {
      _publishOrRetain(receivedDuringDrain);
    }
  }

  StrongAlert? takePending() {
    final alert = _pending;
    _pending = null;
    return alert;
  }

  void _publishOrRetain(StrongAlert alert) {
    if (_controller.hasListener) {
      _pending = null;
      _controller.add(alert);
    } else {
      _pending = alert;
    }
  }
}
