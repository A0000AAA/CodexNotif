import 'package:codex_notif/background/mail_monitor_task.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selectNewMessagesAfterUid filters duplicates and orders by UID', () {
    final messages = <MimeMessage>[
      MimeMessage()..uid = 105,
      MimeMessage()..uid = 103,
      MimeMessage(),
      MimeMessage()..uid = 104,
      MimeMessage()..uid = 102,
    ];

    final selected = selectNewMessagesAfterUid(messages, 102);

    expect(selected.map((message) => message.uid), [103, 104, 105]);
  });
}
