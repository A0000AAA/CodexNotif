import 'package:flutter_test/flutter_test.dart';

import 'package:codex_notif/services/background_service.dart';

void main() {
  test('monitoring continues in background but stops when task is removed', () {
    final options = BackgroundService.createForegroundTaskOptions();

    expect(options.autoRunOnBoot, isFalse);
    expect(options.autoRunOnMyPackageReplaced, isFalse);
    expect(options.allowAutoRestart, isFalse);
    expect(options.stopWithTask, isTrue);
  });
}
