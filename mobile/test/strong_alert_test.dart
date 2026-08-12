import 'package:codex_notif/models/strong_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strong alert payload round trips with its session token', () {
    const alert = StrongAlert(
      notificationId: 42,
      sessionToken: 'session-42',
      sender: 'bot@example.com',
      subject: 'Done',
      matchedRule: 'subject: Done',
      soundUri: 'android.resource://org.codexnotif.mobile/raw/tone_phone',
    );

    expect(StrongAlert.fromPayload(alert.toPayload()), alert);
  });

  test('count round trips and old payload has safe legacy defaults', () {
    const alert = StrongAlert(
      notificationId: 42,
      sessionToken: 'session-42',
      sender: 'sender@example.test',
      subject: 'Completed',
      matchedRule: 'subject',
      count: 3,
    );
    expect(StrongAlert.fromPayload(alert.toPayload()), alert);
    expect(
      StrongAlert.fromPayload(
        '{"type":"strongAlert","notificationId":42}',
      ),
      isA<StrongAlert>()
          .having((alert) => alert.count, 'count', 1)
          .having((alert) => alert.sessionToken, 'sessionToken', ''),
    );
  });

  test('invalid strong alert payload is ignored', () {
    expect(StrongAlert.fromPayload(null), isNull);
    expect(StrongAlert.fromPayload('not json'), isNull);
    expect(StrongAlert.fromPayload('[]'), isNull);
    expect(
      StrongAlert.fromPayload('{"sender":"bot@example.com"}'),
      isNull,
    );
  });
}
