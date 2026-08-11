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
