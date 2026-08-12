import 'package:codex_notif/models/strong_alert.dart';
import 'package:codex_notif/services/strong_alert_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const firstAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'first@example.test',
    subject: 'First',
    matchedRule: 'subject',
  );
  const updatedAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-first',
    sender: 'latest@example.test',
    subject: 'Latest',
    matchedRule: 'subject',
    count: 2,
  );
  const nextSessionAlert = StrongAlert(
    notificationId: 48202,
    sessionToken: 'session-next',
    sender: 'next@example.test',
    subject: 'Next session',
    matchedRule: 'subject',
  );

  test('same session token updates one presentation', () {
    final presentation = StrongAlertPresentation();

    final first = presentation.openOrUpdate(firstAlert);
    final second = presentation.openOrUpdate(updatedAlert);

    expect(first.created, isTrue);
    expect(second.created, isFalse);
    expect(identical(first.listenable, second.listenable), isTrue);
    expect(second.listenable.value.count, 2);
  });

  test('new token creates a new presentation despite the fixed id', () {
    final presentation = StrongAlertPresentation();

    final first = presentation.openOrUpdate(firstAlert);
    final next = presentation.openOrUpdate(nextSessionAlert);

    expect(first.created, isTrue);
    expect(next.created, isTrue);
    expect(identical(first.listenable, next.listenable), isFalse);
    expect(presentation.remove(firstAlert.sessionToken), first.listenable);
    expect(presentation.remove(nextSessionAlert.sessionToken), next.listenable);
  });
}
