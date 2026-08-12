import 'package:codex_notif/models/imap_mailbox_option.dart';
import 'package:codex_notif/services/qq_mail_service.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folder options start with INBOX and exclude non-selectable nodes', () {
    final folders = <Mailbox>[
      mailbox('Sent Messages', [MailboxFlag.sent]),
      mailbox('任务通知', [MailboxFlag.select]),
      mailbox('Group', [MailboxFlag.noSelect]),
      mailbox('Virtual', [MailboxFlag.virtual]),
      mailbox('INBOX', [MailboxFlag.inbox]),
    ];

    final options = selectableMailboxOptions(folders);

    expect(
      options.map((item) => (item.path, item.isInbox)),
      <(String, bool)>[
        ('INBOX', true),
        ('Sent Messages', false),
        ('任务通知', false),
      ],
    );
  });

  test('folder option uses the server display name and exact path', () {
    final folder = Mailbox(
      encodedName: '通知',
      encodedPath: 'Parent/通知',
      flags: [MailboxFlag.select],
      pathSeparator: '/',
    );

    final option = selectableMailboxOptions([folder]).firstWhere(
      (item) => !item.isInbox,
    );

    expect(option.displayName, '通知');
    expect(option.path, 'Parent/通知');
  });

  test('top-level recursive LIST and LSUB folders merge by exact path', () {
    final inbox = mailbox('INBOX', [MailboxFlag.inbox]);
    final customFromList = mailbox('任务通知', [MailboxFlag.select]);
    final customFromSubscription = mailbox('任务通知', [MailboxFlag.subscribed]);
    final subscriptionOnly = mailbox('自动提醒', [MailboxFlag.subscribed]);

    final merged = mergeMailboxLists(
      [inbox, customFromList],
      [customFromSubscription, subscriptionOnly],
    );

    expect(merged.map((item) => item.path), [
      'INBOX',
      '任务通知',
      '自动提醒',
    ]);
  });

  test('manual Chinese mailbox paths are encoded segment by segment', () {
    final encoded = encodeImapMailboxPath('父级/通知', '/');

    expect(
      encoded,
      '${Mailbox.encode('父级', '/')}/${Mailbox.encode('通知', '/')}',
    );
    expect(encoded, isNot(contains('父级')));
    expect(encoded, isNot(contains('通知')));
  });

  test('detects when QQ exposes only its standard system mailboxes', () {
    final systemOnly = selectableMailboxOptions([
      mailbox('INBOX', [MailboxFlag.inbox]),
      mailbox('Deleted Messages', [MailboxFlag.trash]),
      mailbox('Drafts', [MailboxFlag.drafts]),
      mailbox('Junk', [MailboxFlag.junk]),
      mailbox('Sent Messages', [MailboxFlag.sent]),
    ]);
    final withCustom = [
      ...systemOnly,
      const ImapMailboxOption(
        path: '其他文件夹/任务通知',
        displayName: '任务通知',
        isInbox: false,
      ),
    ];

    expect(hasQqCustomMailboxOption(systemOnly), isFalse);
    expect(hasQqCustomMailboxOption(withCustom), isTrue);
  });
}

Mailbox mailbox(String path, List<MailboxFlag> flags) => Mailbox(
      encodedName: path,
      encodedPath: path,
      flags: flags,
      pathSeparator: '/',
    );
