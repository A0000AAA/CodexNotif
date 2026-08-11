import 'dart:convert';

class StrongAlert {
  const StrongAlert({
    required this.notificationId,
    required this.sender,
    required this.subject,
    required this.matchedRule,
    this.soundUri = 'android.resource://org.codexnotif.mobile/raw/tone_phone',
  });

  final int notificationId;
  final String sender;
  final String subject;
  final String matchedRule;
  final String soundUri;

  String toPayload() => jsonEncode({
        'type': 'strongAlert',
        'notificationId': notificationId,
        'sender': sender,
        'subject': subject,
        'matchedRule': matchedRule,
        'soundUri': soundUri,
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
        sender: value['sender']?.toString() ?? '',
        subject: value['subject']?.toString() ?? '',
        matchedRule: value['matchedRule']?.toString() ?? '',
        soundUri: value['soundUri']?.toString().isNotEmpty == true
            ? value['soundUri'].toString()
            : 'android.resource://org.codexnotif.mobile/raw/tone_phone',
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
          sender == other.sender &&
          subject == other.subject &&
          matchedRule == other.matchedRule &&
          soundUri == other.soundUri;

  @override
  int get hashCode => Object.hash(
        notificationId,
        sender,
        subject,
        matchedRule,
        soundUri,
      );
}
