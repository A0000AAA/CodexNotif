import 'mail_rule.dart';

class AppConfig {
  final String email;
  final String authCode;
  final String imapMailboxPath;
  final bool monitoringEnabled;
  final List<MailRule> rules;

  const AppConfig({
    this.email = '',
    this.authCode = '',
    this.imapMailboxPath = '',
    this.monitoringEnabled = false,
    this.rules = const [],
  });

  bool get hasCredentials =>
      email.trim().isNotEmpty && authCode.trim().isNotEmpty;

  AppConfig copyWith({
    String? email,
    String? authCode,
    String? imapMailboxPath,
    bool? monitoringEnabled,
    List<MailRule>? rules,
  }) {
    return AppConfig(
      email: email ?? this.email,
      authCode: authCode ?? this.authCode,
      imapMailboxPath: imapMailboxPath ?? this.imapMailboxPath,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'authCode': authCode,
        'imapMailboxPath': imapMailboxPath,
        'monitoringEnabled': monitoringEnabled,
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      email: json['email']?.toString() ?? '',
      authCode: json['authCode']?.toString() ?? '',
      imapMailboxPath: json['imapMailboxPath']?.toString() ?? '',
      monitoringEnabled: json['monitoringEnabled'] == true,
      rules: (json['rules'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => MailRule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
