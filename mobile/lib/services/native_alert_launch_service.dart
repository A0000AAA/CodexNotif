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

  Stream<StrongAlert> get alerts => _controller.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showStrongAlert') {
        _accept(call.arguments?.toString());
      }
    });
    _accept(await _channel.invokeMethod<String>('takePendingStrongAlert'));
  }

  StrongAlert? takePending() {
    final alert = _pending;
    _pending = null;
    return alert;
  }

  void _accept(String? payload) {
    final alert = StrongAlert.fromPayload(payload);
    if (alert == null) return;
    _pending = alert;
    _controller.add(alert);
  }
}
