import 'package:codex_notif/models/monitor_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('health is stale when no scan has ever completed', () {
    const health = MonitorHealth();

    expect(health.isStale(DateTime.utc(2026, 8, 11)), isTrue);
  });

  test('health remains fresh for ninety seconds', () {
    final health = MonitorHealth(
      lastScanAt: DateTime.utc(2026, 8, 11, 1),
      lastScanText: '01:00:00 · 没有新邮件',
    );

    expect(
      health.isStale(DateTime.utc(2026, 8, 11, 1, 1, 30)),
      isFalse,
    );
  });

  test('health is stale after ninety seconds without a scan', () {
    final health = MonitorHealth(
      lastScanAt: DateTime.utc(2026, 8, 11, 1),
      lastScanText: '01:00:00 · 没有新邮件',
    );

    expect(
      health.isStale(DateTime.utc(2026, 8, 11, 1, 1, 31)),
      isTrue,
    );
  });

  test('stored primitive values restore monitor health', () {
    final health = MonitorHealth.fromStored(
      epochMilliseconds: DateTime.utc(2026, 8, 11, 1).millisecondsSinceEpoch,
      text: '01:00:00 · 发现 1 封新邮件',
      newMessageCount: 1,
    );

    expect(health.lastScanAt, DateTime.utc(2026, 8, 11, 1));
    expect(health.lastScanText, '01:00:00 · 发现 1 封新邮件');
    expect(health.newMessageCount, 1);
  });
}
