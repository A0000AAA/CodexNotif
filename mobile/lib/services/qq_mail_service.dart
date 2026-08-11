import 'package:enough_mail/enough_mail.dart';

import '../models/app_config.dart';

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
}
