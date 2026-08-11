enum RuleType {
  subject,
  sender,
}

enum AlertSound {
  soft,
  chime,
  alert,
  phone,
  systemLocal,
}

enum AlertMode {
  normal,
  strong,
}

class MailRule {
  final String id;
  final RuleType type;
  final String pattern;
  final AlertSound sound;
  final AlertMode alertMode;
  final bool enabled;

  /// Android system ringtone / notification URI chosen by the user.
  /// Only used when [sound] == AlertSound.systemLocal.
  final String? systemSoundUri;

  /// User-visible title returned by Android's ringtone picker.
  final String? systemSoundTitle;

  const MailRule({
    required this.id,
    required this.type,
    required this.pattern,
    required this.sound,
    this.alertMode = AlertMode.normal,
    this.enabled = true,
    this.systemSoundUri,
    this.systemSoundTitle,
  });

  MailRule copyWith({
    String? id,
    RuleType? type,
    String? pattern,
    AlertSound? sound,
    AlertMode? alertMode,
    bool? enabled,
    String? systemSoundUri,
    String? systemSoundTitle,
    bool clearSystemSound = false,
  }) {
    return MailRule(
      id: id ?? this.id,
      type: type ?? this.type,
      pattern: pattern ?? this.pattern,
      sound: sound ?? this.sound,
      alertMode: alertMode ?? this.alertMode,
      enabled: enabled ?? this.enabled,
      systemSoundUri:
          clearSystemSound ? null : (systemSoundUri ?? this.systemSoundUri),
      systemSoundTitle:
          clearSystemSound ? null : (systemSoundTitle ?? this.systemSoundTitle),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'pattern': pattern,
        'sound': sound.name,
        'alertMode': alertMode.name,
        'enabled': enabled,
        'systemSoundUri': systemSoundUri,
        'systemSoundTitle': systemSoundTitle,
      };

  factory MailRule.fromJson(Map<String, dynamic> json) {
    return MailRule(
      id: json['id']?.toString() ?? '',
      type: RuleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RuleType.subject,
      ),
      pattern: json['pattern']?.toString() ?? '',
      sound: AlertSound.values.firstWhere(
        (e) => e.name == json['sound'],
        orElse: () => AlertSound.alert,
      ),
      alertMode: AlertMode.values.firstWhere(
        (e) => e.name == json['alertMode'],
        orElse: () => AlertMode.normal,
      ),
      enabled: json['enabled'] != false,
      systemSoundUri: json['systemSoundUri']?.toString(),
      systemSoundTitle: json['systemSoundTitle']?.toString(),
    );
  }
}

extension AlertModeInfo on AlertMode {
  String get label => switch (this) {
        AlertMode.normal => '普通提醒',
        AlertMode.strong => '强提醒',
      };

  String get description => switch (this) {
        AlertMode.normal => '播放一次，按系统通知行为结束',
        AlertMode.strong => '全屏显示并持续响铃，直到确认',
      };
}

extension RuleTypeLabel on RuleType {
  String get label => switch (this) {
        RuleType.subject => '主题包含',
        RuleType.sender => '发件人 / 联系人包含',
      };
}

extension AlertSoundInfo on AlertSound {
  String get label => switch (this) {
        AlertSound.soft => '柔和提示',
        AlertSound.chime => '清脆铃声',
        AlertSound.alert => '醒目提醒',
        AlertSound.phone => '电话铃声',
        AlertSound.systemLocal => '手机本地声音',
      };

  String? get rawName => switch (this) {
        AlertSound.soft => 'tone_soft',
        AlertSound.chime => 'tone_chime',
        AlertSound.alert => 'tone_alert',
        AlertSound.phone => 'tone_phone',
        AlertSound.systemLocal => null,
      };
}
