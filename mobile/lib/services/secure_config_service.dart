import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_config.dart';

class SecureConfigService {
  static const _key = 'qq_mail_pager_config_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static Future<AppConfig> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return const AppConfig();
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const AppConfig();
      }

      return AppConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const AppConfig();
    }
  }

  static Future<void> save(AppConfig config) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(config.toJson()),
    );
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
