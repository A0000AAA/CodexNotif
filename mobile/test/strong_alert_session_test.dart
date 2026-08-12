import 'package:codex_notif/background/strong_alert_session.dart';
import 'package:codex_notif/models/strong_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('later mail keeps first sound and increments one session', () {
    const first = StrongAlert(
      notificationId: 48202,
      sessionToken: 'session-first',
      sender: 'first@example.test',
      subject: 'First',
      matchedRule: 'first rule',
      soundUri: 'content://sound/first',
    );
    const latest = StrongAlert(
      notificationId: 48202,
      sessionToken: 'session-latest',
      sender: 'latest@example.test',
      subject: 'Latest',
      matchedRule: 'latest rule',
      soundUri: 'content://sound/latest',
    );

    final merged = mergeStrongAlert(first, latest);

    expect(merged.count, 2);
    expect(merged.subject, 'Latest');
    expect(merged.soundUri, 'content://sound/first');
    expect(merged.notificationId, 48202);
    expect(merged.sessionToken, 'session-first');
  });
}
