import 'package:codex_notif/models/strong_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strong alert payload round trips', () {
    const alert = StrongAlert(
      notificationId: 42,
      sender: 'bot@example.com',
      subject: 'Done',
      matchedRule: 'subject: Done',
      soundUri: 'android.resource://org.codexnotif.mobile/raw/tone_phone',
    );

    expect(StrongAlert.fromPayload(alert.toPayload()), alert);
  });

  test('count round trips and old payload defaults to one', () {
    const alert = StrongAlert(
      notificationId: 42,
      sender: 'sender@example.test',
      subject: 'Completed',
      matchedRule: 'subject',
      count: 3,
    );
    expect(StrongAlert.fromPayload(alert.toPayload()), alert);
    expect(
      StrongAlert.fromPayload(
        '{"type":"strongAlert","notificationId":42}',
      )?.count,
      1,
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
