import 'dart:async';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/app_config.dart';
import '../models/mail_rule.dart';
import '../models/monitor_health.dart';
import '../services/notification_service.dart';
import '../services/qq_mail_service.dart';
import '../services/secure_config_service.dart';
import '../services/system_sound_service.dart';
import 'resilient_poll_loop.dart';

@pragma('vm:entry-point')
void foregroundStartCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(
    MailMonitorTaskHandler(),
  );
}

class MailMonitorTaskHandler extends TaskHandler {
  MailClient? _client;

  ResilientPollLoop? _pollLoop;

  AppConfig _config = const AppConfig();

  bool _connecting = false;
  bool _scanning = false;
  bool _destroyed = false;
  int _lastSeenUid = 0;

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

    try {
      final savedUid = await FlutterForegroundTask.getData(
        key: 'last_seen_uid_service_fix',
      );

      if (savedUid is int) {
        _lastSeenUid = savedUid;
      } else if (savedUid is String) {
        _lastSeenUid = int.tryParse(savedUid) ?? 0;
      }
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'status',
        'text': '读取 UID 状态失败，但后台服务继续运行：$e',
      });
    }

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

      final inbox = await client.selectInbox();

      if (_lastSeenUid == 0) {
        _lastSeenUid = await _latestUid(client, inbox);
        if (_lastSeenUid > 0) {
          await FlutterForegroundTask.saveData(
            key: 'last_seen_uid_service_fix',
            value: _lastSeenUid,
          );
        }
      }

      // QQ IMAP IDLE is not reliable on every Android/HyperOS background
      // connection. Always perform an explicit UID scan as well, so missed
      // MailLoadEvents are recovered deterministically.
      await _scanSafely();

      await FlutterForegroundTask.updateService(
        notificationTitle: 'QQ 邮箱提醒器正在监听',
        notificationText: 'QQ IMAP 已连接；匹配规则的邮件才会响',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'status',
        'text': '后台服务正常；QQ IMAP 已连接',
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
    final uidNext = inbox.uidNext;
    if (uidNext != null && uidNext > 0) {
      return uidNext - 1;
    }

    final latest = await client.fetchMessages(
      count: 1,
      fetchPreference: FetchPreference.envelope,
    );
    return latest.isEmpty ? 0 : latest.first.uid ?? 0;
  }

  Future<void> _scanSafely() async {
    if (_scanning || _destroyed) return;

    final client = _client;
    if (client == null || !client.isConnected) return;

    _scanning = true;
    try {
      final inbox = await client.selectInbox();
      final latestUid = await _latestUid(client, inbox);
      final previousUid = _lastSeenUid;

      if (latestUid <= previousUid) {
        await _reportScan(0);
        return;
      }

      final fetched = await client.fetchMessageSequence(
        MessageSequence.fromRange(
          previousUid + 1,
          latestUid,
          isUidSequence: true,
        ),
        fetchPreference: FetchPreference.envelope,
      );
      final messages = selectNewMessagesAfterUid(fetched, previousUid);

      for (final message in messages) {
        await _handleMessage(message);
      }
      await _reportScan(messages.length);
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

  Future<void> _reportScan(int newMessageCount) async {
    final now = DateTime.now();
    final time = [now.hour, now.minute, now.second]
        .map((part) => part.toString().padLeft(2, '0'))
        .join(':');
    final text =
        '$time · ${newMessageCount == 0 ? '没有新邮件' : '发现 $newMessageCount 封新邮件'}';

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
        notificationText: '监听正常 · 最近检查 $time',
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

      _lastSeenUid = uid;

      await FlutterForegroundTask.saveData(
        key: 'last_seen_uid_service_fix',
        value: uid,
      );
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
      final strongAlert = await NotificationService.instance.showMatchedMail(
        rule: matched,
        sender: senderText,
        subject: subject,
        matchedRule: '${matched.type.label}「${matched.pattern}」',
      );
      if (strongAlert != null) {
        // The foreground-task FlutterEngine remains alive after the app UI is
        // swiped away. Start the native looping player from this engine before
        // asking the optional main UI isolate to show the full-screen page.
        await SystemSoundService.startAlert(strongAlert.soundUri);
        FlutterForegroundTask.sendDataToMain({
          'type': 'strongAlert',
          'payload': strongAlert.toPayload(),
        });
      }
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'text': '邮件已匹配，但通知播放失败：$e',
      });
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
    if (data is Map && data['command'] == 'reload') {
      unawaited(_connectSafely());
    }
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    bool isTimeout,
  ) async {
    _destroyed = true;
    _pollLoop?.stop();
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

    if (client == null) return;

    if (client.isConnected) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }
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
