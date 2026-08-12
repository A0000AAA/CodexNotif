import 'package:enough_mail/enough_mail.dart';

import '../models/app_config.dart';
import '../models/imap_mailbox_option.dart';

class QqMailService {
  static MailAccount createAccount(AppConfig config) {
    final email = config.email.trim();
    final authCode = config.authCode.trim();

    return MailAccount.fromManualSettings(
      name: 'QQ 邮箱',
      email: email,
      userName: email,
      loginName: email,
      password: authCode,
      incomingHost: 'imap.qq.com',
      outgoingHost: 'smtp.qq.com',
      incomingType: ServerType.imap,
      outgoingType: ServerType.smtp,
      incomingPort: 993,
      outgoingPort: 465,
      incomingSocketType: SocketType.ssl,
      outgoingSocketType: SocketType.ssl,
    );
  }

  static Future<void> testLogin(AppConfig config) async {
    if (!config.hasCredentials) {
      throw StateError('请先填写 QQ 邮箱和授权码。');
    }

    final client = MailClient(
      createAccount(config),
      isLogEnabled: false,
      downloadSizeLimit: 32 * 1024,
      defaultWriteTimeout: const Duration(seconds: 8),
      defaultResponseTimeout: const Duration(seconds: 12),
    );

    try {
      await client.connect(timeout: const Duration(seconds: 15));
      await client.selectInbox();

      // 只抓一封 envelope 验证读信，不下载正文或附件。
      await client.fetchMessages(
        count: 1,
        fetchPreference: FetchPreference.envelope,
      );
    } finally {
      if (client.isConnected) {
        await client.disconnect();
      }
    }
  }

  static Future<List<ImapMailboxOption>> listSelectableMailboxes(
    AppConfig config,
  ) async {
    if (!config.hasCredentials) {
      throw StateError('请先填写 QQ 邮箱和授权码。');
    }

    final client = MailClient(
      createAccount(config),
      isLogEnabled: false,
      downloadSizeLimit: 32 * 1024,
      defaultWriteTimeout: const Duration(seconds: 8),
      defaultResponseTimeout: const Duration(seconds: 12),
    );

    try {
      await client.connect(timeout: const Duration(seconds: 15));
      return selectableMailboxOptions(await listAllMailboxes(client));
    } finally {
      if (client.isConnected) {
        await client.disconnect();
      }
    }
  }

  static Future<List<Mailbox>> listAllMailboxes(MailClient client) async {
    final listed = await client.listMailboxes();
    final lowLevel = client.lowLevelIncomingMailClient;
    if (lowLevel is! ImapClient) return listed;

    var allListed = listed;
    try {
      final recursive = await lowLevel.listMailboxes(recursive: true);
      allListed = mergeMailboxLists(listed, recursive);
    } catch (_) {
      // Keep the standard top-level LIST result when recursive LIST is not
      // supported by a server.
    }

    try {
      final subscribed = await lowLevel.listSubscribedMailboxes(
        recursive: true,
      );
      return mergeMailboxLists(allListed, subscribed);
    } catch (_) {
      // Recursive LIST is the standard source. LSUB is an extra compatibility
      // path for servers that expose user folders only as subscriptions.
      return allListed;
    }
  }

  static Future<Mailbox> selectMailbox(
    MailClient client,
    List<Mailbox> mailboxes,
    String configuredPath,
  ) async {
    final path = configuredPath.trim();
    if (path.isEmpty || path.toUpperCase() == 'INBOX') {
      final inbox = findInbox(mailboxes);
      if (inbox == null) {
        throw StateError('QQ IMAP 未返回根收件箱。');
      }
      return client.selectMailbox(inbox);
    }

    final listed = findSelectableMailbox(mailboxes, path);
    if (listed != null) {
      return client.selectMailbox(listed);
    }

    final lowLevel = client.lowLevelIncomingMailClient;
    if (lowLevel is! ImapClient) {
      throw StateError('当前邮箱连接不支持直接选择文件夹。');
    }

    // Some QQ accounts omit custom folders from LIST and LSUB even though the
    // folder can still be selected by its exact IMAP path.
    final separator = lowLevel.serverInfo.pathSeparator ?? '/';
    final encodedPath = encodeImapMailboxPath(path, separator);
    final direct = await lowLevel.selectMailboxByPath(encodedPath);
    return client.selectMailbox(direct);
  }

  static Future<void> validateMailboxPath(
    AppConfig config,
    String mailboxPath,
  ) async {
    if (!config.hasCredentials) {
      throw StateError('请先填写 QQ 邮箱和授权码。');
    }
    if (mailboxPath.trim().isEmpty) {
      throw StateError('文件夹名称不能为空。');
    }

    final client = MailClient(
      createAccount(config),
      isLogEnabled: false,
      downloadSizeLimit: 32 * 1024,
      defaultWriteTimeout: const Duration(seconds: 8),
      defaultResponseTimeout: const Duration(seconds: 12),
    );

    try {
      await client.connect(timeout: const Duration(seconds: 15));
      final mailboxes = await listAllMailboxes(client);
      await selectMailbox(client, mailboxes, mailboxPath);
    } finally {
      if (client.isConnected) {
        await client.disconnect();
      }
    }
  }
}

String encodeImapMailboxPath(String path, String pathSeparator) => path
    .split(pathSeparator)
    .map((segment) => Mailbox.encode(segment, pathSeparator))
    .join(pathSeparator);

Mailbox? findInbox(Iterable<Mailbox> mailboxes) {
  for (final mailbox in mailboxes) {
    if (mailbox.isInbox || mailbox.path.toUpperCase() == 'INBOX') {
      return mailbox;
    }
  }
  return null;
}

Mailbox? findSelectableMailbox(
  Iterable<Mailbox> mailboxes,
  String path,
) {
  for (final mailbox in mailboxes) {
    if (mailbox.path == path &&
        !mailbox.flags.contains(MailboxFlag.noSelect) &&
        !mailbox.flags.contains(MailboxFlag.virtual)) {
      return mailbox;
    }
  }
  return null;
}

List<Mailbox> mergeMailboxLists(
  Iterable<Mailbox> listed,
  Iterable<Mailbox> subscribed,
) {
  final byPath = <String, Mailbox>{};
  for (final mailbox in [...listed, ...subscribed]) {
    byPath.putIfAbsent(mailbox.path, () => mailbox);
  }
  return byPath.values.toList();
}

List<ImapMailboxOption> selectableMailboxOptions(
  Iterable<Mailbox> mailboxes,
) {
  final selectable = mailboxes
      .where(
        (mailbox) =>
            !mailbox.flags.contains(MailboxFlag.noSelect) &&
            !mailbox.flags.contains(MailboxFlag.virtual) &&
            !mailbox.isInbox,
      )
      .map(
        (mailbox) => ImapMailboxOption(
          path: mailbox.path,
          displayName: mailbox.name,
          isInbox: false,
        ),
      )
      .toList()
    ..sort(
      (left, right) => left.displayName
          .toLowerCase()
          .compareTo(right.displayName.toLowerCase()),
    );

  return [
    const ImapMailboxOption(
      path: 'INBOX',
      displayName: '根收件箱（INBOX）',
      isInbox: true,
    ),
    ...selectable,
  ];
}

bool hasQqCustomMailboxOption(Iterable<ImapMailboxOption> options) {
  const systemPaths = {
    'INBOX',
    'Deleted Messages',
    'Drafts',
    'Junk',
    'Sent Messages',
  };
  return options.any((option) => !systemPaths.contains(option.path));
}
