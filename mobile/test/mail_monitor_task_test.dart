import 'dart:async';
import 'dart:io';

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

  test('commits a UID only after its message is handled successfully',
      () async {
    final messages = <MimeMessage>[
      MimeMessage()..uid = 201,
      MimeMessage()..uid = 202,
    ];
    final handled = <int>[];
    final committed = <int>[];

    final lastSeenUid = await processMessagesAndCommitUid(
      messages: messages,
      lastSeenUid: 200,
      handleMessage: (message) async => handled.add(message.uid!),
      commitUid: (uid) async => committed.add(uid),
    );

    expect(handled, [201, 202]);
    expect(committed, [201, 202]);
    expect(lastSeenUid, 202);
  });

  test('does not commit a failed message or any message after it', () async {
    final messages = <MimeMessage>[
      MimeMessage()..uid = 201,
      MimeMessage()..uid = 202,
      MimeMessage()..uid = 203,
    ];
    final handled = <int>[];
    final committed = <int>[];

    await expectLater(
      processMessagesAndCommitUid(
        messages: messages,
        lastSeenUid: 200,
        handleMessage: (message) async {
          handled.add(message.uid!);
          if (message.uid == 202) {
            throw StateError('notification failed');
          }
        },
        commitUid: (uid) async => committed.add(uid),
      ),
      throwsA(isA<StateError>()),
    );

    expect(handled, [201, 202]);
    expect(committed, [201]);
  });

  test('background mail isolate does not invoke activity-only audio channel',
      () {
    final source =
        File('lib/background/mail_monitor_task.dart').readAsStringSync();

    expect(source, isNot(contains('SystemSoundService.startAlert')));
  });

  test('scan summary exposes saved and server UIDs for IMAP diagnosis', () {
    final text = buildScanReportText(
      now: DateTime(2026, 8, 12, 13, 20, 9),
      newMessageCount: 0,
      savedUid: 120,
      serverLatestUid: 118,
      uidValidity: 456,
    );

    expect(
      text,
      '13:20:09 · 没有新邮件 · 根收件箱（INBOX） · UID 已存 120 / 服务器 118 · UIDVALIDITY 456',
    );
  });

  test('new mail scan always fetches from saved UID through server last', () {
    final sequence = newUidFetchSequence(5156);

    expect(sequence.isUidSequence, isTrue);
    expect(sequence.toString(), '5157:*');
  });

  test('cursor keys are scoped by account folder and UIDVALIDITY', () {
    final inbox = mailboxCursorKey('USER@example.com', '', 10);

    expect(inbox, mailboxCursorKey('user@example.com', 'inbox', 10));
    expect(inbox, isNot(mailboxCursorKey('other@example.com', '', 10)));
    expect(
      inbox,
      isNot(mailboxCursorKey('user@example.com', '任务通知', 10)),
    );
    expect(inbox, isNot(mailboxCursorKey('user@example.com', '', 11)));
  });

  test('configured mailbox matches the exact selectable server path', () {
    final folder = testMailbox('任务通知', [MailboxFlag.select]);
    final parent = testMailbox('codex', [MailboxFlag.noSelect]);

    expect(
      findConfiguredMailbox([folder, parent], '任务通知'),
      same(folder),
    );
    expect(findConfiguredMailbox([folder, parent], 'Codex 通知'), isNull);
    expect(findConfiguredMailbox([folder, parent], 'codex'), isNull);
  });

  test('a hidden configured folder requires direct IMAP selection', () {
    final inbox = testMailbox('INBOX', [MailboxFlag.inbox]);
    final visible = testMailbox('Visible', [MailboxFlag.select]);

    expect(
      requiresDirectMailboxSelection([inbox, visible], '任务通知'),
      isTrue,
    );
    expect(
      requiresDirectMailboxSelection([inbox, visible], 'Visible'),
      isFalse,
    );
    expect(requiresDirectMailboxSelection([inbox, visible], ''), isFalse);
  });

  test('fallback requires an explicit missing-mailbox server error', () {
    final inbox = testMailbox('INBOX', [MailboxFlag.inbox]);

    expect(
      shouldFallbackToInbox(
        error: StateError('Folder not exist!'),
        isConnected: true,
        mailboxes: [inbox],
        configuredPath: '任务通知',
      ),
      isTrue,
    );
    expect(
      shouldFallbackToInbox(
        error: TimeoutException('temporary timeout'),
        isConnected: true,
        mailboxes: [inbox],
        configuredPath: '任务通知',
      ),
      isFalse,
    );
    expect(
      shouldFallbackToInbox(
        error: StateError('Folder not exist!'),
        isConnected: false,
        mailboxes: [inbox],
        configuredPath: '任务通知',
      ),
      isFalse,
    );
  });
}

Mailbox testMailbox(String path, List<MailboxFlag> flags) => Mailbox(
      encodedName: path,
      encodedPath: path,
      flags: flags,
      pathSeparator: '/',
    );
