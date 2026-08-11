import 'package:codex_notif/models/mail_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy JSON defaults to normal alert mode', () {
    final rule = MailRule.fromJson({
      'id': 'legacy',
      'type': 'subject',
      'pattern': 'Agent Pager',
      'sound': 'alert',
    });

    expect(rule.alertMode, AlertMode.normal);
  });

  test('strong alert mode survives JSON round trip', () {
    const rule = MailRule(
      id: 'strong',
      type: RuleType.sender,
      pattern: 'codex_notif',
      sound: AlertSound.phone,
      alertMode: AlertMode.strong,
    );

    expect(MailRule.fromJson(rule.toJson()).alertMode, AlertMode.strong);
  });

  test('unknown alert mode falls back to normal', () {
    final rule = MailRule.fromJson({
      'id': 'unknown',
      'type': 'subject',
      'pattern': 'Done',
      'sound': 'alert',
      'alertMode': 'future_mode',
    });

    expect(rule.alertMode, AlertMode.normal);
  });
}
