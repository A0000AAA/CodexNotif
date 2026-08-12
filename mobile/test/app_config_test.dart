import 'package:codex_notif/models/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old config defaults to the root inbox', () {
    final config = AppConfig.fromJson({
      'email': 'user@example.com',
      'monitoringEnabled': true,
    });

    expect(config.imapMailboxPath, isEmpty);
  });

  test('IMAP mailbox path survives a JSON round trip', () {
    const config = AppConfig(imapMailboxPath: '任务通知');

    expect(
      AppConfig.fromJson(config.toJson()).imapMailboxPath,
      '任务通知',
    );
  });

  test('copyWith can select and clear an IMAP mailbox path', () {
    const config = AppConfig(imapMailboxPath: '任务通知');

    expect(config.copyWith(imapMailboxPath: '工作').imapMailboxPath, '工作');
    expect(config.copyWith(imapMailboxPath: '').imapMailboxPath, isEmpty);
  });
}
