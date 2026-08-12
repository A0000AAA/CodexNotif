import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/mail_rule.dart';
import '../models/strong_alert.dart';
import 'system_sound_service.dart';

const int strongAlertNotificationId = 48202;

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
}) {
  final strong = mode == AlertMode.strong;
  final useAlarmAudio = strong || forceAlarmAudio;

  return AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: '由 QQ 邮箱规则匹配触发',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: sound,
    enableVibration: true,
    autoCancel: !strong,
    ongoing: strong,
    category: strong
        ? AndroidNotificationCategory.alarm
        : AndroidNotificationCategory.message,
    fullScreenIntent: strong,
    additionalFlags: strong ? Int32List.fromList(const [4]) : null,
    actions: strong
        ? const [
            AndroidNotificationAction(
              'acknowledge',
              '我知道了',
              cancelNotification: true,
              showsUserInterface: true,
            ),
          ]
        : null,
    audioAttributesUsage: useAlarmAudio
        ? AudioAttributesUsage.alarm
        : AudioAttributesUsage.notification,
    styleInformation: BigTextStyleInformation(
      '$sender\n$subject\n规则：$matchedRule',
      contentTitle: subject.isEmpty ? '收到匹配邮件' : subject,
      summaryText: sender,
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
    if (response.actionId == 'acknowledge') {
      unawaited(SystemSoundService.stopAlert());
      return;
    }

    final alert = StrongAlert.fromPayload(response.payload);
    if (alert == null) return;

    if (retainForStartup) _pendingStrongAlert = alert;
    _strongAlertController.add(alert);
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
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final sound = notificationSoundForRule(rule);
    final effectiveMode = preview ? AlertMode.normal : rule.alertMode;
    final channelId = _channelIdForRule(rule, preview: preview);
    final channelName = preview
        ? '试听 · ${_soundDisplayName(rule)}'
        : '${rule.alertMode.label} · ${_soundDisplayName(rule)}';
    final strong = effectiveMode == AlertMode.strong;
    final useAlarmAudio = strong || preview;

    // Android 8+: channel owns the sound. A new sound selection gets a new
    // deterministic channel ID so changing sound takes effect immediately.
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
        audioAttributesUsage: useAlarmAudio
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      ),
    );

    final notificationId = notificationIdForAlert(effectiveMode);
    final strongAlert = strong
        ? StrongAlert(
            notificationId: notificationId,
            sender: sender,
            subject: subject,
            matchedRule: matchedRule,
            soundUri: playbackUriForRule(rule),
          )
        : null;
    final details = NotificationDetails(
      android: buildAndroidNotificationDetails(
        mode: effectiveMode,
        channelId: channelId,
        channelName: channelName,
        sound: sound,
        sender: sender,
        subject: subject,
        matchedRule: matchedRule,
        forceAlarmAudio: preview,
      ),
    );

    await _plugin.show(
      notificationId,
      subject.isEmpty ? '收到匹配邮件' : subject,
      sender.isEmpty ? 'QQ 邮箱规则匹配' : sender,
      details,
      payload: strongAlert?.toPayload(),
    );
    return strongAlert;
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
