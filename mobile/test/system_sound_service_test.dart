import 'package:codex_notif/services/system_sound_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.codexnotif.mobile/system_sound');
  const backgroundAudioChannel =
      MethodChannel('org.codexnotif.mobile/background_audio');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundAudioChannel, null);
  });

  test('pick sends existing URI and maps native result', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, Object>{
        'uri': 'content://new',
        'title': '哈基米系统闹铃_&_4560e5bf-c5a9-4779-afc9-a5dc10ae0c08.mp3',
      };
    });

    final sound = await SystemSoundService.pick(existingUri: 'content://old');

    expect(captured?.method, 'pickSound');
    expect(captured?.arguments, {'existingUri': 'content://old'});
    expect(sound?.uri, 'content://new');
    expect(sound?.title, '哈基米系统闹铃');
  });

  test('picker cancellation returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await SystemSoundService.pick(), isNull);
  });

  test('ensurePersistent asks Android to migrate the ringtone URI', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return 'content://media/external/audio/media/42';
    });

    final uri = await SystemSoundService.ensurePersistent(
      uri: 'content://temporary/ringtone',
      title: '电话铃声',
    );

    expect(captured?.method, 'persistSound');
    expect(captured?.arguments, {
      'uri': 'content://temporary/ringtone',
      'title': '电话铃声',
    });
    expect(uri, 'content://media/external/audio/media/42');
  });

  test('preview uses activity channel and alerts use background channel',
      () async {
    final activityMethods = <String>[];
    final backgroundMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      activityMethods.add(call.method);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backgroundAudioChannel, (call) async {
      backgroundMethods.add(call.method);
      return null;
    });

    await SystemSoundService.previewOnce('android.resource://tone');
    await SystemSoundService.startAlert('content://media/ringtone');
    await SystemSoundService.stopPreview();
    await SystemSoundService.stopAlert();

    expect(activityMethods, [
      'previewSound',
      'stopPreviewSound',
    ]);
    expect(backgroundMethods, [
      'startAlertSound',
      'stopAlertSound',
    ]);
  });
}
