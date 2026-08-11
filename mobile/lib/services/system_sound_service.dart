import 'package:flutter/services.dart';

class PickedSystemSound {
  final String uri;
  final String title;

  const PickedSystemSound({
    required this.uri,
    required this.title,
  });
}

class SystemSoundService {
  static const _channel =
      MethodChannel('org.codexnotif.mobile/system_sound');
  static const _backgroundAudioChannel =
      MethodChannel('org.codexnotif.mobile/background_audio');

  static Future<PickedSystemSound?> pick({
    String? existingUri,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickSound',
      {
        'existingUri': existingUri,
      },
    );

    if (result == null) return null;

    final uri = result['uri']?.toString() ?? '';
    if (uri.isEmpty) return null;

    return PickedSystemSound(
      uri: uri,
      title: _cleanTitle(result['title']?.toString()),
    );
  }

  static Future<String> ensurePersistent({
    required String uri,
    required String title,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'persistSound',
      {
        'uri': uri,
        'title': title,
      },
    );
    return result?.isNotEmpty == true ? result! : uri;
  }

  static Future<void> previewOnce(String uri) =>
      _channel.invokeMethod<void>('previewSound', {'uri': uri});

  static Future<void> startAlert(String uri) =>
      _backgroundAudioChannel.invokeMethod<void>(
        'startAlertSound',
        {'uri': uri},
      );

  static Future<void> stopPreview() =>
      _channel.invokeMethod<void>('stopPreviewSound');

  static Future<void> stopAlert() =>
      _backgroundAudioChannel.invokeMethod<void>('stopAlertSound');

  static String _cleanTitle(String? value) {
    final title = value?.trim() ?? '';
    if (title.isEmpty) return '手机本地声音';

    return title.replaceFirst(
      RegExp(
        r'_&_[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.[a-z0-9]{2,5}$',
        caseSensitive: false,
      ),
      '',
    );
  }
}
