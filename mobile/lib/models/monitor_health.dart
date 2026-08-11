class MonitorHealth {
  const MonitorHealth({
    this.lastScanAt,
    this.lastScanText = '',
    this.newMessageCount = 0,
  });

  static const lastScanEpochKey = 'monitor_last_scan_epoch_ms';
  static const lastScanTextKey = 'monitor_last_scan_text';
  static const lastScanNewCountKey = 'monitor_last_scan_new_count';

  final DateTime? lastScanAt;
  final String lastScanText;
  final int newMessageCount;

  factory MonitorHealth.fromStored({
    int? epochMilliseconds,
    String? text,
    int? newMessageCount,
  }) {
    return MonitorHealth(
      lastScanAt: epochMilliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              epochMilliseconds,
              isUtc: true,
            ),
      lastScanText: text ?? '',
      newMessageCount: newMessageCount ?? 0,
    );
  }

  bool isStale(
    DateTime now, {
    Duration threshold = const Duration(seconds: 90),
  }) {
    final scanAt = lastScanAt;
    if (scanAt == null) return true;
    return now.difference(scanAt) > threshold;
  }
}
