import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/app_config.dart';
import '../models/mail_rule.dart';
import '../models/monitor_health.dart';
import '../services/notification_service.dart';
import '../services/qq_mail_service.dart';
import '../services/secure_config_service.dart';
import '../services/strong_alert_platform_service.dart';
import 'resilient_poll_loop.dart';
import 'strong_alert_coordinator.dart';

@pragma('vm:entry-point')
void foregroundStartCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(
    MailMonitorTaskHandler(),
  );
}

class MailMonitorTaskHandler extends TaskHandler {
  MailClient? _client;
  Mailbox? _selectedMailbox;

  late final StrongAlertCoordinator _strongAlerts = StrongAlertCoordinator(
    startAudio: StrongAlertPlatformService.startAudio,
    stopAudio: StrongAlertPlatformService.stopAudio,
    showNotification: (alert, {required isUpdate}) =>
        NotificationService.instance.showStrongAlert(
          alert,
          isUpdate: isUpdate,
        ),
    requestFullScreen: StrongAlertPlatformService.requestFullScreen,
    cancelNotification: NotificationService.instance.cancel,
    publish: (alert) => FlutterForegroundTask.sendDataToMain({
      'type': 'strongAlert',
      'payload': alert.toPayload(),
    }),
    publishAcknowledged: (id) => FlutterForegroundTask.sendDataToMain({
      'type': 'strongAlertAcknowledged',
      'notificationId': id,
    }),
  );

  ResilientPollLoop? _pollLoop;

  AppConfig _config = const AppConfig();

  bool _connecting = false;
  bool _scanning = false;
  bool _destroyed = false;
  int _lastSeenUid = 0;
  String? _cursorKey;
  String _activeMailboxLabel = '根收件箱（INBOX）';
  String? _mailboxFallbackNotice;

  @override
  Future<void> onStart(
    DateTime timestamp,
    TaskStarter starter,
  ) async {
    // IMPORTANT:
    // Starting the foreground service and connecting IMAP are separate things.
    // Any IMAP/config/plugin failure must NOT terminate the FGS.
    FlutterForegroundTask.sendDataToMain({
      'type': 'service',
      'running': true,
      'text': 'Android 前台服务已运行，准备连接 QQ 邮箱',
    });

    _pollLoop?.stop();
    _pollLoop = ResilientPollLoop(
      interval: const Duration(seconds: 30),
      onPoll: _pollOnce,
    );
    _pollLoop!.start();

    // A restarted foreground service gets a fresh Dart isolate. Run one scan
    // immediately, then let the Dart-owned timer keep polling even when the
    // plugin's native repeat callback is not restored by HyperOS.
    await _pollLoop!.pollNow();
  }

  Future<void> _pollOnce() async {
    if (_destroyed) return;

    if (_client?.isConnected == true) {
      await _scanSafely();
    } else {
      await _connectSafely();
    }
  }

  Future<void> _connectSafely() async {
    if (_connecting || _destroyed) return;

    _connecting = true;

    try {
      await _disconnectClient();

      _config = await SecureConfigService.load();

      if (!_config.monitoringEnabled) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'QQ 邮箱提醒器后台服务已运行',
          notificationText: '监听开关当前关闭',
        );

        FlutterForegroundTask.sendDataToMain({
          'type': 'status',
          'text': '前台服务正常，但“后台监听”开关当前关闭',
        });
        return;
      }

      if (!_config.hasCredentials) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'QQ 邮箱提醒器后台服务已运行',
          notificationText: '请在 App 中填写 QQ 邮箱和授权码',
        );

        FlutterForegroundTask.sendDataToMain({
          'type': 'status',
          'text': '前台服务正常，但 QQ 邮箱/授权码尚未配置',
        });
        return;
      }

      final client = MailClient(
        QqMailService.createAccount(_config),
        isLogEnabled: false,
        downloadSizeLimit: 32 * 1024,
        defaultWriteTimeout: const Duration(seconds: 8),
        defaultResponseTimeout: const Duration(seconds: 12),
      );

      _client = client;

      await FlutterForegroundTask.updateService(
        notificationTitle: 'QQ 邮箱提醒器后台服务已运行',
        notificationText: '正在连接 imap.qq.com:993',
      );

      await client.connect(
        timeout: const Duration(seconds: 15),
      );

      final mailboxes = await QqMailService.listAllMailboxes(client);
      final configuredPath = _config.imapMailboxPath.trim();
      _mailboxFallbackNotice = null;

      try {
        _selectedMailbox = await QqMailService.selectMailbox(
          client,
          mailboxes,
          configuredPath,
        );
      } catch (error) {
        final canFallback = shouldFallbackToInbox(
          error: error,
          isConnected: client.isConnected,
          mailboxes: mailboxes,
          configuredPath: configuredPath,
        );
        if (!canFallback) rethrow;

        final oldPath = configuredPath;
        _selectedMailbox = await QqMailService.selectMailbox(
          client,
          mailboxes,
          '',
        );
        _config = _config.copyWith(imapMailboxPath: '');
        await SecureConfigService.save(_config);
        _mailboxFallbackNotice = '监听文件夹“$oldPath”不可用，已回退根收件箱';
      }

      _activeMailboxLabel =
          _selectedMailbox!.isInbox ? '根收件箱（INBOX）' : _selectedMailbox!.name;
      await _activateMailboxCursor(client, _selectedMailbox!);

      // QQ IMAP IDLE is not reliable on every Android/HyperOS background
      // connection. Always perform an explicit UID scan as well, so missed
      // MailLoadEvents are recovered deterministically.
      await _scanSafely();

      final fallbackNotice = _mailboxFallbackNotice;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'QQ 邮箱提醒器正在监听',
        notificationText:
            fallbackNotice ?? '正在监听 $_activeMailboxLabel；匹配规则的邮件才会响',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': fallbackNotice == null ? 'status' : 'mailboxFallback',
        'text': fallbackNotice ?? '后台服务正常；正在监听 $_activeMailboxLabel',
      });
    } catch (e, stack) {
      // Do NOT throw. Keep the Android FGS alive and retry later.
      await FlutterForegroundTask.updateService(
        notificationTitle: 'QQ 邮箱提醒器后台服务已运行',
        notificationText: 'QQ IMAP 连接失败，30 秒后重试',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'text': '后台服务正常，但 QQ IMAP 连接失败：$e',
        'stack': stack.toString(),
      });

      await _disconnectClient();
    } finally {
      _connecting = false;
    }
  }

  Future<int> _latestUid(MailClient client, Mailbox inbox) async {
    final latest = await client.fetchMessages(
      count: 1,
      fetchPreference: FetchPreference.envelope,
    );
    if (latest.isNotEmpty && latest.first.uid != null) {
      return latest.first.uid!;
    }
    final uidNext = inbox.uidNext;
    return uidNext != null && uidNext > 0 ? uidNext - 1 : 0;
  }

  Future<void> _activateMailboxCursor(
    MailClient client,
    Mailbox mailbox,
  ) async {
    final key = mailboxCursorKey(
      _config.email,
      mailbox.path,
      mailbox.uidValidity,
    );
    if (_cursorKey == key) return;

    final stored = await FlutterForegroundTask.getData(key: key);
    final savedUid = parseStoredUid(stored);
    _cursorKey = key;
    if (savedUid != null) {
      _lastSeenUid = savedUid;
      return;
    }

    _lastSeenUid = await _latestUid(client, mailbox);
    await FlutterForegroundTask.saveData(key: key, value: _lastSeenUid);
  }

  Future<void> _scanSafely() async {
    if (_scanning || _destroyed) return;

    final client = _client;
    if (client == null || !client.isConnected) return;

    _scanning = true;
    try {
      final selected = _selectedMailbox;
      if (selected == null) return;
      final mailbox = await client.selectMailbox(selected);
      _selectedMailbox = mailbox;
      _activeMailboxLabel = mailbox.isInbox ? '根收件箱（INBOX）' : mailbox.name;
      await _activateMailboxCursor(client, mailbox);
      final advertisedLatestUid = await _latestUid(client, mailbox);
      final previousUid = _lastSeenUid;

      final fetched = await client.fetchMessageSequence(
        newUidFetchSequence(previousUid),
        fetchPreference: FetchPreference.envelope,
      );
      final messages = selectNewMessagesAfterUid(fetched, previousUid);
      var observedLatestUid = advertisedLatestUid;
      for (final message in fetched) {
        final uid = message.uid;
        if (uid != null && uid > observedLatestUid) {
          observedLatestUid = uid;
        }
      }
      await processMessagesAndCommitUid(
        messages: messages,
        lastSeenUid: previousUid,
        handleMessage: _handleMessage,
        commitUid: (uid) async {
          final cursorKey = _cursorKey;
          if (cursorKey == null) {
            throw StateError('IMAP UID 游标尚未初始化。');
          }
          await FlutterForegroundTask.saveData(
            key: cursorKey,
            value: uid,
          );
          _lastSeenUid = uid;
        },
      );
      await _reportScan(
        messages.length,
        savedUid: _lastSeenUid,
        serverLatestUid: observedLatestUid,
        uidValidity: mailbox.uidValidity,
        mailboxLabel: _activeMailboxLabel,
        notice: _mailboxFallbackNotice,
      );
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'text': 'QQ IMAP 主动检查失败，30 秒后重连：$e',
      });
      await _disconnectClient();
    } finally {
      _scanning = false;
    }
  }

  Future<void> _reportScan(
    int newMessageCount, {
    required int savedUid,
    required int serverLatestUid,
    required int? uidValidity,
    required String mailboxLabel,
    String? notice,
  }) async {
    final now = DateTime.now();
    final time = formatScanTime(now);
    final text = buildScanReportText(
      now: now,
      newMessageCount: newMessageCount,
      savedUid: savedUid,
      serverLatestUid: serverLatestUid,
      uidValidity: uidValidity,
      mailboxLabel: mailboxLabel,
      notice: notice,
    );

    try {
      await Future.wait([
        FlutterForegroundTask.saveData(
          key: MonitorHealth.lastScanEpochKey,
          value: now.toUtc().millisecondsSinceEpoch,
        ),
        FlutterForegroundTask.saveData(
          key: MonitorHealth.lastScanTextKey,
          value: text,
        ),
        FlutterForegroundTask.saveData(
          key: MonitorHealth.lastScanNewCountKey,
          value: newMessageCount,
        ),
      ]);
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'status',
        'text': 'IMAP 检查成功，但保存检查时间失败：$e',
      });
    }

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'QQ 邮箱提醒器正在监听',
        notificationText: notice ?? '监听 $mailboxLabel 正常 · 最近检查 $time',
      );
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'status',
        'text': 'IMAP 检查成功，但更新通知栏状态失败：$e',
      });
    }

    FlutterForegroundTask.sendDataToMain({
      'type': 'scan',
      'text': text,
    });
  }

  Future<void> _handleMessage(MimeMessage message) async {
    final uid = message.uid;

    if (uid != null) {
      if (uid <= _lastSeenUid) return;
    }

    _config = await SecureConfigService.load();
    if (!_config.monitoringEnabled) return;

    final subject = message.decodeSubject()?.trim() ?? '';

    final senderList = message.decodeSender(combine: true);

    final senderText = senderList
        .map(
          (e) => [
            if (e.personalName?.trim().isNotEmpty == true)
              e.personalName!.trim(),
            e.email.trim(),
          ].join(' '),
        )
        .join(', ')
        .trim();

    final matched = _firstMatchingRule(
      _config.rules,
      senderText,
      subject,
    );

    FlutterForegroundTask.sendDataToMain({
      'type': matched == null ? 'mail' : 'match',
      'sender': senderText,
      'subject': subject,
      'rule': matched?.pattern ?? '',
    });

    if (matched == null) return;

    try {
      final matchedRule = '${matched.type.label}「${matched.pattern}」';
      if (matched.alertMode == AlertMode.strong) {
        final latest = createStrongAlert(
          rule: matched,
          sender: senderText,
          subject: subject,
          matchedRule: matchedRule,
        );
        await _strongAlerts.add(latest);
      } else {
        await NotificationService.instance.showNormalMatchedMail(
          rule: matched,
          sender: senderText,
          subject: subject,
          matchedRule: matchedRule,
        );
      }
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'text': '邮件已匹配，但通知播放失败：$e',
      });
      rethrow;
    }
  }

  MailRule? _firstMatchingRule(
    List<MailRule> rules,
    String sender,
    String subject,
  ) {
    final senderLower = sender.toLowerCase();
    final subjectLower = subject.toLowerCase();

    for (final rule in rules) {
      if (!rule.enabled) continue;

      final pattern = rule.pattern.trim().toLowerCase();

      if (pattern.isEmpty) continue;

      final candidate = switch (rule.type) {
        RuleType.sender => senderLower,
        RuleType.subject => subjectLower,
      };

      if (candidate.contains(pattern)) {
        return rule;
      }
    }

    return null;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final pollLoop = _pollLoop;
    unawaited(pollLoop == null ? _pollOnce() : pollLoop.pollNow());
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    if (data['command'] == 'reload') {
      unawaited(_connectSafely());
    } else if (data['command'] == 'acknowledgeStrongAlert') {
      unawaited(
        _strongAlerts.acknowledge(
          notificationId: parseStoredUid(data['notificationId']),
        ),
      );
    }
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    bool isTimeout,
  ) async {
    _destroyed = true;
    _pollLoop?.stop();
    await _strongAlerts.dispose();
    await _disconnectClient();

    FlutterForegroundTask.sendDataToMain({
      'type': 'service',
      'running': false,
      'text': 'Android 前台服务已停止',
    });
  }

  Future<void> _disconnectClient() async {
    final client = _client;
    _client = null;
    _selectedMailbox = null;
    _cursorKey = null;
    _lastSeenUid = 0;

    if (client == null) return;

    if (client.isConnected) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }
}

MessageSequence newUidFetchSequence(int lastSeenUid) =>
    MessageSequence.fromRangeToLast(
      lastSeenUid + 1,
      isUidSequence: true,
    );

String formatScanTime(DateTime now) => [now.hour, now.minute, now.second]
    .map((part) => part.toString().padLeft(2, '0'))
    .join(':');

String buildScanReportText({
  required DateTime now,
  required int newMessageCount,
  required int savedUid,
  required int serverLatestUid,
  required int? uidValidity,
  String mailboxLabel = '根收件箱（INBOX）',
  String? notice,
}) {
  final result = newMessageCount == 0 ? '没有新邮件' : '发现 $newMessageCount 封新邮件';
  final base =
      '${formatScanTime(now)} · $result · $mailboxLabel · UID 已存 $savedUid / 服务器 $serverLatestUid · UIDVALIDITY ${uidValidity ?? '未知'}';
  return notice == null ? base : '$base · $notice';
}

String mailboxCursorKey(
  String email,
  String mailboxPath,
  int? uidValidity,
) {
  final account = email.trim().toLowerCase();
  final rawPath = mailboxPath.trim();
  final folder =
      rawPath.isEmpty || rawPath.toUpperCase() == 'INBOX' ? 'INBOX' : rawPath;
  final identity = '$account\n$folder\n${uidValidity ?? 0}';
  return 'last_seen_uid_v2_${base64Url.encode(utf8.encode(identity))}';
}

int? parseStoredUid(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

Mailbox? findConfiguredMailbox(
  Iterable<Mailbox> mailboxes,
  String configuredPath,
) {
  for (final mailbox in mailboxes) {
    if (mailbox.path == configuredPath &&
        !mailbox.flags.contains(MailboxFlag.noSelect) &&
        !mailbox.flags.contains(MailboxFlag.virtual)) {
      return mailbox;
    }
  }
  return null;
}

bool requiresDirectMailboxSelection(
  Iterable<Mailbox> mailboxes,
  String configuredPath,
) {
  final path = configuredPath.trim();
  return path.isNotEmpty &&
      path.toUpperCase() != 'INBOX' &&
      findConfiguredMailbox(mailboxes, path) == null;
}

bool shouldFallbackToInbox({
  required Object error,
  required bool isConnected,
  required Iterable<Mailbox> mailboxes,
  required String configuredPath,
}) {
  if (!isConnected ||
      !requiresDirectMailboxSelection(mailboxes, configuredPath)) {
    return false;
  }

  final message = error.toString().toLowerCase();
  return message.contains('folder not exist') ||
      message.contains('unknown mailbox') ||
      message.contains('[nonexistent]') ||
      message.contains('mailbox does not exist');
}

List<MimeMessage> selectNewMessagesAfterUid(
  Iterable<MimeMessage> messages,
  int lastSeenUid,
) {
  final selected = messages
      .where((message) => message.uid != null && message.uid! > lastSeenUid)
      .toList();
  selected.sort((left, right) => left.uid!.compareTo(right.uid!));
  return selected;
}

Future<int> processMessagesAndCommitUid({
  required Iterable<MimeMessage> messages,
  required int lastSeenUid,
  required Future<void> Function(MimeMessage message) handleMessage,
  required Future<void> Function(int uid) commitUid,
}) async {
  var committedUid = lastSeenUid;

  for (final message in messages) {
    final uid = message.uid;
    if (uid == null || uid <= committedUid) continue;

    await handleMessage(message);
    await commitUid(uid);
    committedUid = uid;
  }

  return committedUid;
}
