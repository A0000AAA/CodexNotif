import 'dart:async';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/mail_rule.dart';
import '../models/strong_alert.dart';
import 'strong_alert_platform_service.dart';
import 'system_sound_service.dart';

const int strongAlertNotificationId = 48202;
const String strongAlertChannelId = 'mail_strong_alert_silent_v2';

String strongAlertTitle(StrongAlert alert) => alert.count > 1
    ? '收到多封匹配邮件'
    : (alert.subject.isEmpty ? '收到匹配邮件' : alert.subject);

String strongAlertBody(StrongAlert alert) {
  if (alert.count == 1) {
    return alert.sender.isEmpty ? 'QQ 邮箱规则匹配' : alert.sender;
  }
  final latest = alert.subject.isEmpty ? '最新邮件无主题' : alert.subject;
  return '共 ${alert.count} 封 · 最新：$latest';
}

StrongAlert createStrongAlert({
  required MailRule rule,
  required String sender,
  required String subject,
  required String matchedRule,
}) => StrongAlert(
    notificationId: strongAlertNotificationId,
    sender: sender,
    subject: subject,
    matchedRule: matchedRule,
    soundUri: playbackUriForRule(rule),
  );

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  NotificationService.handleNotificationResponse(response);
}

int notificationIdForAlert(
  AlertMode mode, {
  int? timestampMillis,
}) {
  if (mode == AlertMode.strong) return strongAlertNotificationId;
  return (timestampMillis ?? DateTime.now().millisecondsSinceEpoch)
      .remainder(1 << 31);
}

String playbackUriForRule(MailRule rule) {
  if (rule.sound == AlertSound.systemLocal) {
    final uri = rule.systemSoundUri;
    if (uri != null && uri.isNotEmpty) return uri;
  }
  return 'android.resource://org.codexnotif.mobile/raw/${rule.sound.rawName ?? 'tone_phone'}';
}

AndroidNotificationSound notificationSoundForRule(MailRule rule) {
  if (rule.sound == AlertSound.systemLocal) {
    final uri = rule.systemSoundUri;

    if (uri != null && uri.isNotEmpty) {
      return UriAndroidNotificationSound(uri);
    }

    return const RawResourceAndroidNotificationSound('tone_alert');
  }

  return RawResourceAndroidNotificationSound(rule.sound.rawName!);
}

AndroidNotificationDetails buildAndroidNotificationDetails({
  required AlertMode mode,
  required String channelId,
  required String channelName,
  required AndroidNotificationSound sound,
  required String sender,
  required String subject,
  required String matchedRule,
  bool forceAlarmAudio = false,
  bool isStrongUpdate = false,
  StrongAlert? strongAlert,
}) {
  final strong = mode == AlertMode.strong;
  final useAlarmAudio = strong || forceAlarmAudio;
  final aggregatedStrongAlert = strongAlert != null && strongAlert.count > 1
      ? strongAlert
      : null;

  return AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: '由 QQ 邮箱规则匹配触发',
    importance: strong ? Importance.high : Importance.max,
    priority: Priority.high,
    playSound: !strong,
    sound: strong ? null : sound,
    onlyAlertOnce: strong,
    enableVibration: strong ? !isStrongUpdate : true,
    autoCancel: !strong,
    ongoing: strong,
    category: strong
        ? AndroidNotificationCategory.alarm
        : AndroidNotificationCategory.message,
    fullScreenIntent: strong && !isStrongUpdate,
    additionalFlags: null,
    actions: strong
        ? const [
            AndroidNotificationAction(
              'acknowledge',
              '我知道了',
              cancelNotification: true,
              showsUserInterface: false,
            ),
          ]
        : null,
    audioAttributesUsage: useAlarmAudio
        ? AudioAttributesUsage.alarm
        : AudioAttributesUsage.notification,
    styleInformation: BigTextStyleInformation(
      aggregatedStrongAlert == null
          ? '$sender\n$subject\n规则：$matchedRule'
          : strongAlertBody(aggregatedStrongAlert),
      contentTitle: aggregatedStrongAlert == null
          ? (subject.isEmpty ? '收到匹配邮件' : subject)
          : strongAlertTitle(aggregatedStrongAlert),
      summaryText: aggregatedStrongAlert == null ? sender : null,
    ),
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<StrongAlert> _strongAlertController =
      StreamController<StrongAlert>.broadcast();

  bool _initialized = false;
  StrongAlert? _pendingStrongAlert;

  Stream<StrongAlert> get strongAlerts => _strongAlertController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if ((launchDetails?.didNotificationLaunchApp ?? false) &&
        launchResponse != null) {
      _handleNotificationResponse(
        launchResponse,
        retainForStartup: true,
      );
    }
    _initialized = true;
  }

  void _handleNotificationResponse(
    NotificationResponse response, {
    bool retainForStartup = false,
  }) {
    handleNotificationResponse(response);

    if (response.actionId == 'acknowledge') return;

    final alert = StrongAlert.fromPayload(response.payload);
    if (alert == null) return;

    if (retainForStartup) _pendingStrongAlert = alert;
    _strongAlertController.add(alert);
  }

  static void handleNotificationResponse(NotificationResponse response) {
    if (response.actionId != 'acknowledge') return;
    unawaited(
      StrongAlertPlatformService.acknowledge(
        response.id ?? strongAlertNotificationId,
      ),
    );
  }

  StrongAlert? takePendingStrongAlert() {
    final alert = _pendingStrongAlert;
    _pendingStrongAlert = null;
    return alert;
  }

  Future<void> requestPermission() async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();
  }

  Future<bool?> requestFullScreenPermission() async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.requestFullScreenIntentPermission();
  }

  Future<void> cancel(int notificationId) async {
    await initialize();
    await _plugin.cancel(notificationId);
  }

  Future<StrongAlert?> showMatchedMail({
    required MailRule rule,
    required String sender,
    required String subject,
    required String matchedRule,
    bool preview = false,
  }) async {
    if (!preview && rule.alertMode == AlertMode.strong) {
      final alert = createStrongAlert(
        rule: rule,
        sender: sender,
        subject: subject,
        matchedRule: matchedRule,
      );
      await showStrongAlert(alert, isUpdate: false);
      return alert;
    }

    await _showNormalMatchedMail(
      rule: rule,
      sender: sender,
      subject: subject,
      matchedRule: matchedRule,
      preview: preview,
    );
    return null;
  }

  Future<void> showStrongAlert(
    StrongAlert alert, {
    required bool isUpdate,
  }) async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        strongAlertChannelId,
        '强提醒（静默）',
        description: '由 QQ 邮箱规则匹配触发',
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
        showBadge: true,
      ),
    );

    final details = NotificationDetails(
      android: buildAndroidNotificationDetails(
        mode: AlertMode.strong,
        channelId: strongAlertChannelId,
        channelName: '强提醒（静默）',
        sound: const RawResourceAndroidNotificationSound('tone_phone'),
        sender: alert.sender,
        subject: alert.subject,
        matchedRule: alert.matchedRule,
        isStrongUpdate: isUpdate,
        strongAlert: alert,
      ),
    );
    await _plugin.show(
      alert.notificationId,
      strongAlertTitle(alert),
      strongAlertBody(alert),
      details,
      payload: alert.toPayload(),
    );
  }

  Future<void> showNormalMatchedMail({
    required MailRule rule,
    required String sender,
    required String subject,
    required String matchedRule,
  }) => _showNormalMatchedMail(
    rule: rule,
    sender: sender,
    subject: subject,
    matchedRule: matchedRule,
  );

  Future<void> _showNormalMatchedMail({
    required MailRule rule,
    required String sender,
    required String subject,
    required String matchedRule,
    bool preview = false,
  }) async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final sound = notificationSoundForRule(rule);
    final channelId = _channelIdForRule(rule, preview: preview);
    final channelName = preview
        ? '试听 · ${_soundDisplayName(rule)}'
        : '${rule.alertMode.label} · ${_soundDisplayName(rule)}';
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        channelName,
        description: '由 QQ 邮箱规则匹配触发',
        importance: Importance.high,
        playSound: true,
        sound: sound,
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: preview
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      ),
    );

    await _plugin.show(
      notificationIdForAlert(AlertMode.normal),
      subject.isEmpty ? '收到匹配邮件' : subject,
      sender.isEmpty ? 'QQ 邮箱规则匹配' : sender,
      NotificationDetails(
        android: buildAndroidNotificationDetails(
          mode: AlertMode.normal,
          channelId: channelId,
          channelName: channelName,
          sound: sound,
          sender: sender,
          subject: subject,
          matchedRule: matchedRule,
          forceAlarmAudio: preview,
        ),
      ),
    );
  }

  Future<void> testRuleSound(MailRule rule) async {
    await initialize();
    await SystemSoundService.previewOnce(playbackUriForRule(rule));
  }

  String _soundDisplayName(MailRule rule) {
    if (rule.sound == AlertSound.systemLocal) {
      return rule.systemSoundTitle?.isNotEmpty == true
          ? rule.systemSoundTitle!
          : '手机本地声音';
    }

    return rule.sound.label;
  }

  String _channelIdForRule(MailRule rule, {bool preview = false}) {
    final soundSignature = rule.sound == AlertSound.systemLocal
        ? '${rule.sound.name}|${rule.systemSoundUri ?? ''}'
        : rule.sound.name;
    final signature =
        '${preview ? 'preview_alarm' : rule.alertMode.name}|$soundSignature';

    return 'mail_${_safeId(rule.id)}_${_fnv1a(signature)}';
  }

  String _safeId(String value) {
    final s = value.replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );

    return s.length <= 24 ? s : s.substring(0, 24);
  }

  String _fnv1a(String input) {
    var hash = 0x811c9dc5;

    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }

    return hash.toRadixString(16);
  }
}
