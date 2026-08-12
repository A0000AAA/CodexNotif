import 'dart:convert';

class StrongAlert {
  const StrongAlert({
    required this.notificationId,
    this.sessionToken = '',
    required this.sender,
    required this.subject,
    required this.matchedRule,
    this.soundUri = 'android.resource://org.codexnotif.mobile/raw/tone_phone',
    this.count = 1,
  });

  final int notificationId;
  final String sessionToken;
  final String sender;
  final String subject;
  final String matchedRule;
  final String soundUri;
  final int count;

  StrongAlert copyWith({
    int? notificationId,
    String? sessionToken,
    String? sender,
    String? subject,
    String? matchedRule,
    String? soundUri,
    int? count,
  }) =>
      StrongAlert(
        notificationId: notificationId ?? this.notificationId,
        sessionToken: sessionToken ?? this.sessionToken,
        sender: sender ?? this.sender,
        subject: subject ?? this.subject,
        matchedRule: matchedRule ?? this.matchedRule,
        soundUri: soundUri ?? this.soundUri,
        count: count ?? this.count,
      );

  String toPayload() => jsonEncode({
        'type': 'strongAlert',
        'notificationId': notificationId,
        'sessionToken': sessionToken,
        'sender': sender,
        'subject': subject,
        'matchedRule': matchedRule,
        'soundUri': soundUri,
        'count': count,
      });

  static StrongAlert? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;

    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic> ||
          value['type'] != 'strongAlert' ||
          value['notificationId'] is! int) {
        return null;
      }

      return StrongAlert(
        notificationId: value['notificationId'] as int,
        sessionToken: value['sessionToken']?.toString() ?? '',
        sender: value['sender']?.toString() ?? '',
        subject: value['subject']?.toString() ?? '',
        matchedRule: value['matchedRule']?.toString() ?? '',
        soundUri: value['soundUri']?.toString().isNotEmpty == true
            ? value['soundUri'].toString()
            : 'android.resource://org.codexnotif.mobile/raw/tone_phone',
        count: switch (value['count']) {
          final int count when count > 0 => count,
          _ => 1,
        },
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongAlert &&
          notificationId == other.notificationId &&
          sessionToken == other.sessionToken &&
          sender == other.sender &&
          subject == other.subject &&
          matchedRule == other.matchedRule &&
          soundUri == other.soundUri &&
          count == other.count;

  @override
  int get hashCode => Object.hash(
        notificationId,
        sessionToken,
        sender,
        subject,
        matchedRule,
        soundUri,
        count,
      );
}
