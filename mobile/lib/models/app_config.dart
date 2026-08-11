import 'mail_rule.dart';

class AppConfig {
  final String email;
  final String authCode;
  final bool monitoringEnabled;
  final List<MailRule> rules;

  const AppConfig({
    this.email = '',
    this.authCode = '',
    this.monitoringEnabled = false,
    this.rules = const [],
  });

  bool get hasCredentials =>
      email.trim().isNotEmpty && authCode.trim().isNotEmpty;

  AppConfig copyWith({
    String? email,
    String? authCode,
    bool? monitoringEnabled,
    List<MailRule>? rules,
  }) {
    return AppConfig(
      email: email ?? this.email,
      authCode: authCode ?? this.authCode,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'authCode': authCode,
        'monitoringEnabled': monitoringEnabled,
        'rules': rules.map((e) => e.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      email: json['email']?.toString() ?? '',
      authCode: json['authCode']?.toString() ?? '',
      monitoringEnabled: json['monitoringEnabled'] == true,
      rules: (json['rules'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => MailRule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
