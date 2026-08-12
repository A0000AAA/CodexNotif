# Android Aggregated Strong Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 客户端把尚未确认的多封匹配邮件合并成一个持续响铃的强提醒，并在确认或服务退出时可靠停止。

**Architecture:** `MailMonitorTaskHandler` 持有一个 `StrongAlertCoordinator`，由协调器维护当前会话、控制前台服务原生播放器并更新固定通知。Flutter 主 isolate 使用可更新的展示控制器复用同一全屏路由；小米最佳努力启动通过原生插件唤起 `MainActivity`，再由独立 MethodChannel 交付提醒载荷。

**Tech Stack:** Flutter/Dart、`flutter_local_notifications`、定制 `flutter_foreground_task`、Android Java/Kotlin、Flutter widget test、Kotlin/JUnit。

## Global Constraints

- 第一封匹配邮件触发一次强提醒，后续未确认邮件合并到固定通知 ID `48202`。
- 多封时标题精确显示“收到多封匹配邮件”，正文显示“共 N 封”和最新邮件摘要。
- 后台原生 `AlertSoundPlayer` 是强提醒唯一音频源；全屏页不得再次启动播放器。
- 后续通知更新不重启声音、不再次请求全屏，也不播放通知渠道声音。
- “我知道了”、服务销毁和最近任务划掉都必须幂等释放播放器。
- `stopWithTask: true`、`allowAutoRestart: false`、不开机自启的现有生命周期保持不变。
- 不新增短信、联系人、通话记录、定位、相机、麦克风或广泛存储权限。
- 不提交真实邮箱、服务器、密钥、设备标识、证书、构建产物或本地绝对路径。
- 只修改 `CodexNotif-Public`；提交信息使用中文；未经再次确认不上传 GitHub Release。

## File Structure

- `mobile/lib/models/strong_alert.dart`：`count` 兼容和复制接口。
- `mobile/lib/background/strong_alert_session.dart`：单会话合并规则。
- `mobile/lib/services/strong_alert_platform_service.dart`：后台音频、全屏和确认命令。
- `mobile/lib/services/notification_service.dart`：普通通知、静默强提醒和通知操作。
- `mobile/lib/background/strong_alert_coordinator.dart`：音频、通知、全屏、发布和清理状态机。
- `mobile/lib/background/mail_monitor_task.dart`：邮件匹配接入与确认命令处理。
- `mobile/lib/services/native_alert_launch_service.dart`：接收原生 Activity 启动载荷。
- `mobile/lib/services/strong_alert_presentation.dart`：同一提醒页面的原位更新。
- `mobile/lib/main.dart`：连接提醒入口和全屏路由。
- `mobile/lib/screens/full_screen_alert_page.dart`：聚合内容展示和确认。
- `mobile/android/app/src/main/java/org/codexnotif/mobile/MainActivity.java`：缓存或推送原生载荷。
- `mobile/third_party/flutter_foreground_task/android/src/main/kotlin/...`：原生播放器、小米启动和服务销毁清理。

---

### Task 1: 强提醒计数与会话合并

**Files:**
- Modify: `mobile/lib/models/strong_alert.dart`
- Create: `mobile/lib/background/strong_alert_session.dart`
- Modify: `mobile/test/strong_alert_test.dart`
- Create: `mobile/test/strong_alert_session_test.dart`

**Interfaces:**
- Consumes: 现有 `StrongAlert(notificationId, sender, subject, matchedRule, soundUri)`。
- Produces: `StrongAlert.count`、`StrongAlert.copyWith(...)`、`mergeStrongAlert(StrongAlert? active, StrongAlert latest)`。

- [ ] **Step 1: 写入失败的载荷兼容和合并测试**

```dart
test('count round trips and old payload defaults to one', () {
  const alert = StrongAlert(
    notificationId: 42,
    sender: 'sender@example.test',
    subject: 'Completed',
    matchedRule: 'subject',
    count: 3,
  );
  expect(StrongAlert.fromPayload(alert.toPayload()), alert);
  expect(
    StrongAlert.fromPayload(
      '{"type":"strongAlert","notificationId":42}',
    )?.count,
    1,
  );
});

test('later mail keeps first sound and increments one session', () {
  const first = StrongAlert(
    notificationId: 48202,
    sender: 'first@example.test',
    subject: 'First',
    matchedRule: 'first rule',
    soundUri: 'content://sound/first',
  );
  const latest = StrongAlert(
    notificationId: 48202,
    sender: 'latest@example.test',
    subject: 'Latest',
    matchedRule: 'latest rule',
    soundUri: 'content://sound/latest',
  );

  final merged = mergeStrongAlert(first, latest);

  expect(merged.count, 2);
  expect(merged.subject, 'Latest');
  expect(merged.soundUri, 'content://sound/first');
  expect(merged.notificationId, 48202);
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `Set-Location mobile; flutter test test/strong_alert_test.dart test/strong_alert_session_test.dart`

Expected: FAIL，提示 `count` 或 `mergeStrongAlert` 尚不存在。

- [ ] **Step 3: 实现模型字段、复制方法和合并函数**

在 `StrongAlert` 构造器和字段中加入：

```dart
this.count = 1,

final int count;

StrongAlert copyWith({
  int? notificationId,
  String? sender,
  String? subject,
  String? matchedRule,
  String? soundUri,
  int? count,
}) => StrongAlert(
      notificationId: notificationId ?? this.notificationId,
      sender: sender ?? this.sender,
      subject: subject ?? this.subject,
      matchedRule: matchedRule ?? this.matchedRule,
      soundUri: soundUri ?? this.soundUri,
      count: count ?? this.count,
    );
```

在 `toPayload`、`operator ==` 和 `hashCode` 中加入 `count`，并在 `fromPayload` 中使用：

```dart
count: switch (value['count']) {
  final int count when count > 0 => count,
  _ => 1,
},
```

新文件写入：

```dart
import '../models/strong_alert.dart';

StrongAlert mergeStrongAlert(StrongAlert? active, StrongAlert latest) {
  if (active == null) return latest.copyWith(count: 1);
  return latest.copyWith(
    notificationId: active.notificationId,
    soundUri: active.soundUri,
    count: active.count + 1,
  );
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `Set-Location mobile; flutter test test/strong_alert_test.dart test/strong_alert_session_test.dart`

Expected: PASS，两个测试文件全部通过。

- [ ] **Step 5: 提交数据模型**

```powershell
git add -- mobile/lib/models/strong_alert.dart mobile/lib/background/strong_alert_session.dart mobile/test/strong_alert_test.dart mobile/test/strong_alert_session_test.dart
git commit -m "feat: 增加强提醒合并会话模型"
```

### Task 2: 后台音频与小米原生启动桥

**Files:**
- Create: `mobile/lib/services/strong_alert_platform_service.dart`
- Create: `mobile/test/strong_alert_platform_service_test.dart`
- Create: `mobile/test/android_background_alert_contract_test.dart`
- Modify: `mobile/third_party/flutter_foreground_task/android/src/main/kotlin/com/pravera/flutter_foreground_task/FlutterForegroundTaskPlugin.kt`
- Modify: `mobile/third_party/flutter_foreground_task/android/src/main/kotlin/com/pravera/flutter_foreground_task/service/AlertSoundPlayer.kt`
- Modify: `mobile/third_party/flutter_foreground_task/android/src/main/kotlin/com/pravera/flutter_foreground_task/service/ForegroundService.kt`
- Create: `mobile/third_party/flutter_foreground_task/android/src/main/kotlin/com/pravera/flutter_foreground_task/service/XiaomiAlertActivityLauncher.kt`
- Create: `mobile/third_party/flutter_foreground_task/android/src/test/kotlin/com/pravera/flutter_foreground_task/service/XiaomiAlertActivityLauncherTest.kt`

**Interfaces:**
- Consumes: MethodChannel `org.codexnotif.mobile/background_audio` 和 `StrongAlert.toPayload()`。
- Produces: `StrongAlertPlatformService.startAudio`、`stopAudio`、`requestFullScreen`、`acknowledge`；原生方法 `showFullScreenAlert`。

- [ ] **Step 1: 写入失败的平台通道和生命周期契约测试**

```dart
test('platform service uses background engine channel', () async {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('org.codexnotif.mobile/background_audio'),
    (call) async {
      calls.add(call);
      return call.method == 'showFullScreenAlert';
    },
  );

  await StrongAlertPlatformService.startAudio('content://sound/selected');
  expect(
    await StrongAlertPlatformService.requestFullScreen('{"type":"strongAlert"}'),
    isTrue,
  );
  await StrongAlertPlatformService.stopAudio();

  expect(calls.map((call) => call.method), [
    'startAlertSound',
    'showFullScreenAlert',
    'stopAlertSound',
  ]);
});
```

`android_background_alert_contract_test.dart` 写入：

```dart
test('native service cleans audio without logging selected URIs', () {
  final root = 'third_party/flutter_foreground_task/android/src/main/kotlin/'
      'com/pravera/flutter_foreground_task';
  final service = File('$root/service/ForegroundService.kt').readAsStringSync();
  final player = File('$root/service/AlertSoundPlayer.kt').readAsStringSync();
  final plugin = File('$root/FlutterForegroundTaskPlugin.kt').readAsStringSync();

  expect(service, contains('AlertSoundPlayer.stop()'));
  expect(player, isNot(contains(r'uri=$candidate')));
  expect(plugin, contains('"showFullScreenAlert"'));
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `Set-Location mobile; flutter test test/strong_alert_platform_service_test.dart test/android_background_alert_contract_test.dart`

Expected: FAIL，提示平台服务或原生清理契约不存在。

- [ ] **Step 3: 实现 Dart 平台服务**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class StrongAlertPlatformService {
  static const _channel =
      MethodChannel('org.codexnotif.mobile/background_audio');

  static Future<void> startAudio(String soundUri) =>
      _channel.invokeMethod<void>('startAlertSound', {'uri': soundUri});

  static Future<void> stopAudio() =>
      _channel.invokeMethod<void>('stopAlertSound');

  static Future<bool> requestFullScreen(String payload) async =>
      await _channel.invokeMethod<bool>(
        'showFullScreenAlert',
        {'payload': payload},
      ) ??
      false;

  static Future<void> acknowledge(int notificationId) async {
    try {
      await stopAudio();
    } catch (_) {
      // The task command remains the authoritative cleanup path.
    } finally {
      FlutterForegroundTask.sendDataToTask({
        'command': 'acknowledgeStrongAlert',
        'notificationId': notificationId,
      });
    }
  }
}
```

- [ ] **Step 4: 实现原生小米启动和隐私安全日志**

`XiaomiAlertActivityLauncher.kt` 写入：

```kotlin
package com.pravera.flutter_foreground_task.service

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

internal object XiaomiAlertActivityLauncher {
    const val EXTRA_STRONG_ALERT_PAYLOAD =
        "org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD"
    private const val TAG = "CodexNotifAlert"

    fun isSupportedManufacturer(manufacturer: String): Boolean {
        val normalized = manufacturer.trim().lowercase()
        return normalized == "xiaomi" || normalized == "redmi" || normalized == "poco"
    }

    fun launch(context: Context, payload: String?): Boolean {
        if (!isSupportedManufacturer(Build.MANUFACTURER) || payload.isNullOrBlank()) {
            return false
        }
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: return false
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        intent.putExtra(EXTRA_STRONG_ALERT_PAYLOAD, payload)
        return try {
            context.startActivity(intent)
            true
        } catch (error: RuntimeException) {
            Log.w(TAG, "System rejected the best-effort alert activity launch")
            false
        }
    }
}
```

插件 MethodChannel 增加：

```kotlin
"showFullScreenAlert" -> result.success(
    XiaomiAlertActivityLauncher.launch(
        binding.applicationContext,
        call.argument<String>("payload"),
    ),
)
```

在 `ForegroundService.onDestroy()` 第一段调用 `AlertSoundPlayer.stop()`；把 `AlertSoundPlayer` 的候选 URI 日志改为只记录启动、停止和异常类名，不输出 URI 文本。

- [ ] **Step 5: 写入 Kotlin 品牌测试并运行原生与 Dart 测试**

```kotlin
package com.pravera.flutter_foreground_task.service

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class XiaomiAlertActivityLauncherTest {
    @Test
    fun recognizesXiaomiFamilyOnly() {
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer("Xiaomi"))
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer("REDMI"))
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer(" poco "))
        assertFalse(XiaomiAlertActivityLauncher.isSupportedManufacturer("Google"))
        assertFalse(XiaomiAlertActivityLauncher.isSupportedManufacturer("Samsung"))
    }
}
```

Run: `Set-Location mobile/android; .\gradlew.bat :flutter_foreground_task:testDebugUnitTest`

Expected: `BUILD SUCCESSFUL`。

Run: `Set-Location mobile; flutter test test/strong_alert_platform_service_test.dart test/android_background_alert_contract_test.dart`

Expected: PASS，通道顺序、服务销毁清理和无 URI 日志契约通过。

- [ ] **Step 6: 提交平台桥**

```powershell
git add -- mobile/lib/services/strong_alert_platform_service.dart mobile/test/strong_alert_platform_service_test.dart mobile/test/android_background_alert_contract_test.dart mobile/third_party/flutter_foreground_task/android
git commit -m "fix: 增加强提醒后台音频与小米启动桥"
```

### Task 3: 静默聚合通知与可靠确认操作

**Files:**
- Modify: `mobile/lib/services/notification_service.dart`
- Modify: `mobile/test/notification_service_test.dart`

**Interfaces:**
- Consumes: `StrongAlert`、`StrongAlertPlatformService.acknowledge(int)`。
- Produces: `createStrongAlert(...)`、`showStrongAlert(StrongAlert, {required bool isUpdate})`、`showNormalMatchedMail(...)`、`strongAlertTitle`、`strongAlertBody`。

- [ ] **Step 1: 写入失败的通知文案和静默更新测试**

```dart
test('aggregated title and body expose one combined reminder', () {
  const alert = StrongAlert(
    notificationId: 48202,
    sender: 'latest@example.test',
    subject: 'Latest task',
    matchedRule: 'subject',
    count: 3,
  );
  expect(strongAlertTitle(alert), '收到多封匹配邮件');
  expect(strongAlertBody(alert), contains('共 3 封'));
  expect(strongAlertBody(alert), contains('Latest task'));
});

test('strong notification delegates sound to native player', () {
  final details = buildAndroidNotificationDetails(
    mode: AlertMode.strong,
    channelId: 'strong',
    channelName: 'Strong',
    sound: const RawResourceAndroidNotificationSound('tone_phone'),
    sender: 'sender@example.test',
    subject: 'Completed',
    matchedRule: 'subject',
    isStrongUpdate: true,
  );
  expect(details.playSound, isFalse);
  expect(details.onlyAlertOnce, isTrue);
  expect(details.enableVibration, isFalse);
  expect(details.additionalFlags, isNull);
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `Set-Location mobile; flutter test test/notification_service_test.dart`

Expected: FAIL，提示聚合文案函数和 `isStrongUpdate` 尚不存在，或强提醒仍启用通知声音。

- [ ] **Step 3: 实现聚合文案和静默通知详情**

```dart
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
```

`buildAndroidNotificationDetails` 增加 `bool isStrongUpdate = false`，强提醒属性使用：

```dart
playSound: !strong,
sound: strong ? null : sound,
onlyAlertOnce: strong,
enableVibration: strong ? !isStrongUpdate : true,
additionalFlags: null,
```

模型构造接口固定为：

```dart
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

Future<void> showStrongAlert(
  StrongAlert alert, {
  required bool isUpdate,
});

Future<void> showNormalMatchedMail({
  required MailRule rule,
  required String sender,
  required String subject,
  required String matchedRule,
});
```

`showStrongAlert` 使用固定渠道 `mail_strong_alert_silent_v2`，渠道 `Importance.high`、`playSound: false`，通知 ID 使用 `alert.notificationId`，标题、正文和 payload 分别使用 `strongAlertTitle(alert)`、`strongAlertBody(alert)`、`alert.toPayload()`。`showNormalMatchedMail` 保留普通通知的动态声音渠道和一次性行为。

- [ ] **Step 4: 将确认操作注册到前台和后台通知回调**

```dart
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  NotificationService.handleNotificationResponse(response);
}

static void handleNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'acknowledge') {
    unawaited(
      StrongAlertPlatformService.acknowledge(
        response.id ?? strongAlertNotificationId,
      ),
    );
    return;
  }
  NotificationService.instance._publishPayload(response.payload);
}
```

初始化插件时传入 `onDidReceiveBackgroundNotificationResponse: notificationTapBackground`；确认按钮使用 `showsUserInterface: false`，避免用户点停止后重新打开应用。

- [ ] **Step 5: 运行通知测试并提交**

Run: `Set-Location mobile; flutter test test/notification_service_test.dart`

Expected: PASS，普通通知仍播放一次，强提醒通知不播放系统声音且聚合文案正确。

```powershell
git add -- mobile/lib/services/notification_service.dart mobile/test/notification_service_test.dart
git commit -m "fix: 合并强提醒通知并统一确认操作"
```

### Task 4: 后台强提醒协调器与邮件处理接入

**Files:**
- Create: `mobile/lib/background/strong_alert_coordinator.dart`
- Create: `mobile/test/strong_alert_coordinator_test.dart`
- Modify: `mobile/lib/background/mail_monitor_task.dart`
- Modify: `mobile/test/mail_monitor_task_test.dart`

**Interfaces:**
- Consumes: `mergeStrongAlert`、`NotificationService.showStrongAlert`、`StrongAlertPlatformService`。
- Produces: `StrongAlertCoordinator.add`、`acknowledge`、`dispose`；任务命令 `acknowledgeStrongAlert`；主 isolate 事件 `strongAlertAcknowledged`。

- [ ] **Step 1: 写入失败的首次、合并、确认和失败恢复测试**

```dart
const firstAlert = StrongAlert(
  notificationId: 48202,
  sender: 'first@example.test',
  subject: 'First',
  matchedRule: 'first rule',
  soundUri: 'content://sound/first',
);
const latestAlert = StrongAlert(
  notificationId: 48202,
  sender: 'latest@example.test',
  subject: 'Latest',
  matchedRule: 'latest rule',
  soundUri: 'content://sound/latest',
);

StrongAlertCoordinator testCoordinator(
  List<String> events, {
  bool failAudio = false,
  bool failNotification = false,
}) =>
    StrongAlertCoordinator(
      startAudio: (uri) async {
        events.add('start:$uri');
        if (failAudio) throw StateError('audio failed');
      },
      stopAudio: () async => events.add('stop'),
      showNotification: (alert, {required isUpdate}) async {
        if (failNotification) throw StateError('notification failed');
        events.add('notify:${alert.count}:$isUpdate');
      },
      requestFullScreen: (payload) async {
        events.add('fullscreen');
        return true;
      },
      cancelNotification: (id) async => events.add('cancel:$id'),
      publish: (alert) => events.add('publish:${alert.count}'),
      publishAcknowledged: (id) => events.add('ack:$id'),
    );

test('first alert starts once and later alerts only update', () async {
  final events = <String>[];
  final coordinator = testCoordinator(events);

  await coordinator.add(firstAlert);
  await coordinator.add(latestAlert);

  expect(events, [
    'start:content://sound/first',
    'notify:1:false',
    'fullscreen',
    'publish:1',
    'notify:2:true',
    'publish:2',
  ]);
});

test('acknowledge stops cancels clears and is idempotent', () async {
  final events = <String>[];
  final coordinator = testCoordinator(events);
  await coordinator.add(firstAlert);
  events.clear();

  await coordinator.acknowledge(notificationId: 48202);
  await coordinator.acknowledge(notificationId: 48202);

  expect(coordinator.activeAlert, isNull);
  expect(events, ['stop', 'cancel:48202', 'ack:48202']);
});

test('notification failure stops audio and rolls session back', () async {
  final events = <String>[];
  final coordinator = testCoordinator(events, failNotification: true);
  await expectLater(coordinator.add(firstAlert), throwsStateError);
  expect(events, ['start:content://sound/first', 'stop']);
  expect(coordinator.activeAlert, isNull);
});

test('audio failure still leaves a visible notification', () async {
  final events = <String>[];
  final coordinator = testCoordinator(events, failAudio: true);
  await coordinator.add(firstAlert);
  expect(events, [
    'start:content://sound/first',
    'notify:1:false',
    'fullscreen',
    'publish:1',
  ]);
});

test('dispose stops playback and removes the active notification', () async {
  final events = <String>[];
  final coordinator = testCoordinator(events);
  await coordinator.add(firstAlert);
  events.clear();
  await coordinator.dispose();
  expect(events, ['stop', 'cancel:48202', 'ack:48202']);
  expect(coordinator.activeAlert, isNull);
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `Set-Location mobile; flutter test test/strong_alert_coordinator_test.dart`

Expected: FAIL，提示 `StrongAlertCoordinator` 尚不存在。

- [ ] **Step 3: 实现可注入、幂等的协调器**

```dart
class StrongAlertCoordinator {
  StrongAlertCoordinator({
    required this.startAudio,
    required this.stopAudio,
    required this.showNotification,
    required this.requestFullScreen,
    required this.cancelNotification,
    required this.publish,
    required this.publishAcknowledged,
  });

  final Future<void> Function(String uri) startAudio;
  final Future<void> Function() stopAudio;
  final Future<void> Function(StrongAlert alert, {required bool isUpdate})
      showNotification;
  final Future<bool> Function(String payload) requestFullScreen;
  final Future<void> Function(int notificationId) cancelNotification;
  final void Function(StrongAlert alert) publish;
  final void Function(int notificationId) publishAcknowledged;

  StrongAlert? _activeAlert;
  int? _lastAcknowledgedId;
  StrongAlert? get activeAlert => _activeAlert;

  Future<StrongAlert> add(StrongAlert latest) async {
    final first = _activeAlert == null;
    final merged = mergeStrongAlert(_activeAlert, latest);
    if (first) {
      try {
        await startAudio(merged.soundUri);
      } catch (_) {}
    }
    try {
      await showNotification(merged, isUpdate: !first);
    } catch (_) {
      if (first) await _stopIgnoringErrors();
      _activeAlert = null;
      rethrow;
    }
    _activeAlert = merged;
    _lastAcknowledgedId = null;
    if (first) {
      try {
        await requestFullScreen(merged.toPayload());
      } catch (_) {}
    }
    publish(merged);
    return merged;
  }

  Future<void> acknowledge({int? notificationId}) async {
    final id = _activeAlert?.notificationId ?? notificationId;
    if (id == null || _lastAcknowledgedId == id) return;
    _activeAlert = null;
    _lastAcknowledgedId = id;
    await _stopIgnoringErrors();
    try {
      await cancelNotification(id);
    } catch (_) {}
    publishAcknowledged(id);
  }

  Future<void> dispose() async {
    final id = _activeAlert?.notificationId;
    _activeAlert = null;
    await _stopIgnoringErrors();
    if (id != null && _lastAcknowledgedId != id) {
      _lastAcknowledgedId = id;
      try {
        await cancelNotification(id);
      } catch (_) {}
      publishAcknowledged(id);
    }
  }

  Future<void> _stopIgnoringErrors() async {
    try {
      await stopAudio();
    } catch (_) {}
  }
}
```

- [ ] **Step 4: 在邮件任务中接入协调器**

`MailMonitorTaskHandler` 创建以下协调器：

```dart
late final StrongAlertCoordinator _strongAlerts = StrongAlertCoordinator(
  startAudio: StrongAlertPlatformService.startAudio,
  stopAudio: StrongAlertPlatformService.stopAudio,
  showNotification: (alert, {required isUpdate}) =>
      NotificationService.instance.showStrongAlert(
        alert,
        isUpdate: isUpdate,
      ),
  requestFullScreen: StrongAlertPlatformService.requestFullScreen,
  cancelNotification: NotificationService.instance.cancel,
  publish: (alert) => FlutterForegroundTask.sendDataToMain({
    'type': 'strongAlert',
    'payload': alert.toPayload(),
  }),
  publishAcknowledged: (id) => FlutterForegroundTask.sendDataToMain({
    'type': 'strongAlertAcknowledged',
    'notificationId': id,
  }),
);
```

强提醒分支先调用 `NotificationService.instance.createStrongAlert(...)`，再调用 `_strongAlerts.add(latest)`；普通提醒调用 `showNormalMatchedMail(...)`。`onReceiveData` 对 `acknowledgeStrongAlert` 调用 `_strongAlerts.acknowledge(notificationId: parsedId)`；`onDestroy` 在断开 IMAP 前调用 `_strongAlerts.dispose()`。

- [ ] **Step 5: 运行协调器和邮件任务测试并提交**

Run: `Set-Location mobile; flutter test test/strong_alert_coordinator_test.dart test/mail_monitor_task_test.dart`

Expected: PASS；第一封只启动一次音频和全屏，后续只更新，确认和销毁都清理。

```powershell
git add -- mobile/lib/background/strong_alert_coordinator.dart mobile/lib/background/mail_monitor_task.dart mobile/test/strong_alert_coordinator_test.dart mobile/test/mail_monitor_task_test.dart
git commit -m "feat: 接入后台强提醒聚合协调器"
```

### Task 5: 原位更新全屏页与冷启动载荷桥

**Files:**
- Create: `mobile/lib/services/native_alert_launch_service.dart`
- Create: `mobile/lib/services/strong_alert_presentation.dart`
- Create: `mobile/test/native_alert_launch_service_test.dart`
- Create: `mobile/test/strong_alert_presentation_test.dart`
- Modify: `mobile/android/app/src/main/java/org/codexnotif/mobile/MainActivity.java`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/screens/full_screen_alert_page.dart`
- Modify: `mobile/test/full_screen_alert_page_test.dart`

**Interfaces:**
- Consumes: 原生 extra `org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD`、`StrongAlertPlatformService.acknowledge`、主 isolate 事件。
- Produces: `NativeAlertLaunchService.alerts`、`takePending`、`StrongAlertPresentation.openOrUpdate`、`FullScreenAlertPage.alertListenable`。

- [ ] **Step 1: 写入失败的原生载荷、展示复用和页面更新测试**

```dart
const firstAlert = StrongAlert(
  notificationId: 48202,
  sender: 'first@example.test',
  subject: 'First',
  matchedRule: 'subject',
);
const secondAlert = StrongAlert(
  notificationId: 48202,
  sender: 'latest@example.test',
  subject: 'Latest',
  matchedRule: 'subject',
  count: 2,
);

test('same notification id updates one presentation', () {
  final presentation = StrongAlertPresentation();
  final first = presentation.openOrUpdate(firstAlert);
  final second = presentation.openOrUpdate(secondAlert);
  expect(first.created, isTrue);
  expect(second.created, isFalse);
  expect(identical(first.listenable, second.listenable), isTrue);
  expect(second.listenable.value.count, 2);
});

testWidgets('page changes to combined title without starting playback',
    (tester) async {
  final alert = ValueNotifier(firstAlert);
  var acknowledged = false;
  await tester.pumpWidget(MaterialApp(
    home: FullScreenAlertPage(
      alertListenable: alert,
      onAcknowledge: () async => acknowledged = true,
    ),
  ));
  alert.value = secondAlert;
  await tester.pump();
  expect(find.text('收到多封匹配邮件'), findsOneWidget);
  expect(find.text('共 2 封'), findsOneWidget);
  await tester.tap(find.text('我知道了，停止响铃'));
  await tester.pump();
  expect(acknowledged, isTrue);
  final source =
      File('lib/screens/full_screen_alert_page.dart').readAsStringSync();
  expect(source, isNot(contains('SystemSoundService.startAlert')));
});
```

`native_alert_launch_service_test.dart` 写入：

```dart
test('native launch payload is retained exactly once', () async {
  const channel = MethodChannel('org.codexnotif.mobile/alert_launch');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'takePendingStrongAlert'
        ? firstAlert.toPayload()
        : null,
  );
  final service = NativeAlertLaunchService();
  await service.initialize();
  expect(service.takePending(), firstAlert);
  expect(service.takePending(), isNull);
});

test('native push is published to the alert stream', () async {
  const channel = MethodChannel('org.codexnotif.mobile/alert_launch');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
  final service = NativeAlertLaunchService();
  await service.initialize();
  final next = service.alerts.first;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('showStrongAlert', firstAlert.toPayload()),
    ),
    (_) {},
  );
  expect(await next, firstAlert);
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `Set-Location mobile; flutter test test/native_alert_launch_service_test.dart test/strong_alert_presentation_test.dart test/full_screen_alert_page_test.dart`

Expected: FAIL，提示服务、展示控制器或 `alertListenable` 尚不存在。

- [ ] **Step 3: 实现原生启动载荷服务和 MainActivity 桥**

`NativeAlertLaunchService` 核心实现：

```dart
class NativeAlertLaunchService {
  NativeAlertLaunchService();
  static final instance = NativeAlertLaunchService();
  static const _channel = MethodChannel('org.codexnotif.mobile/alert_launch');
  final _controller = StreamController<StrongAlert>.broadcast();
  StrongAlert? _pending;

  Stream<StrongAlert> get alerts => _controller.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showStrongAlert') {
        _accept(call.arguments?.toString());
      }
    });
    _accept(await _channel.invokeMethod<String>('takePendingStrongAlert'));
  }

  StrongAlert? takePending() {
    final alert = _pending;
    _pending = null;
    return alert;
  }

  void _accept(String? payload) {
    final alert = StrongAlert.fromPayload(payload);
    if (alert == null) return;
    _pending = alert;
    _controller.add(alert);
  }
}
```

`MainActivity` 增加：

```java
private static final String ALERT_LAUNCH_CHANNEL =
        "org.codexnotif.mobile/alert_launch";
private static final String EXTRA_STRONG_ALERT_PAYLOAD =
        "org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD";
private MethodChannel alertLaunchChannel;
private String pendingStrongAlertPayload;

private void captureStrongAlertPayload(Intent intent, boolean pushNow) {
    if (intent == null) return;
    final String payload = intent.getStringExtra(EXTRA_STRONG_ALERT_PAYLOAD);
    intent.removeExtra(EXTRA_STRONG_ALERT_PAYLOAD);
    if (payload == null || payload.isEmpty()) return;
    if (pushNow && alertLaunchChannel != null) {
        alertLaunchChannel.invokeMethod("showStrongAlert", payload);
    } else {
        pendingStrongAlertPayload = payload;
    }
}
```

在 `configureFlutterEngine` 注册 `takePendingStrongAlert`：读取 `pendingStrongAlertPayload` 后立即清空；随后调用 `captureStrongAlertPayload(getIntent(), false)`。覆盖 `onNewIntent`，执行 `super.onNewIntent(intent)`、`setIntent(intent)` 和 `captureStrongAlertPayload(intent, true)`。

- [ ] **Step 4: 实现展示控制器和无音频全屏页**

```dart
class StrongAlertPresentationUpdate {
  const StrongAlertPresentationUpdate(this.listenable, this.created);
  final ValueNotifier<StrongAlert> listenable;
  final bool created;
}

class StrongAlertPresentation {
  final Map<int, ValueNotifier<StrongAlert>> _alerts = {};

  StrongAlertPresentationUpdate openOrUpdate(StrongAlert alert) {
    final existing = _alerts[alert.notificationId];
    if (existing != null) {
      existing.value = alert;
      return StrongAlertPresentationUpdate(existing, false);
    }
    final created = ValueNotifier(alert);
    _alerts[alert.notificationId] = created;
    return StrongAlertPresentationUpdate(created, true);
  }

  ValueNotifier<StrongAlert>? remove(int notificationId) =>
      _alerts.remove(notificationId);
}
```

`FullScreenAlertPage` 接收 `ValueListenable<StrongAlert> alertListenable`，用 `ValueListenableBuilder` 展示。`count > 1` 时主标题为“收到多封匹配邮件”，数量行显示“共 N 封”；删除 `SystemSoundService.startAlert/stopAlert` 和播放回调。确认按钮的默认路径先调用 `StrongAlertPlatformService.acknowledge(id)`，再取消通知并关闭页面。

- [ ] **Step 5: 在应用根部复用路由并处理确认关闭**

`main()` 在 `runApp` 前执行 `await NativeAlertLaunchService.instance.initialize()`。`QqMailPagerApp` 同时监听通知载荷、前台任务数据和原生启动载荷，三种入口都调用 `_showStrongAlert`。

```dart
void _showStrongAlert(StrongAlert alert) {
  final update = _presentation.openOrUpdate(alert);
  if (!update.created) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FullScreenAlertPage(
        alertListenable: update.listenable,
      ),
    );
    _openRoutes[alert.notificationId] = route;
    await _navigatorKey.currentState?.push<void>(route);
    _openRoutes.remove(alert.notificationId);
    _presentation.remove(alert.notificationId)?.dispose();
  });
}
```

收到 `strongAlertAcknowledged` 时，通过 `_openRoutes[id]` 找到 route 并调用 `NavigatorState.removeRoute(route)`。相同 ID 的重复载荷只更新 notifier，不能再次入栈。

- [ ] **Step 6: 运行界面测试并提交**

Run: `Set-Location mobile; flutter test test/native_alert_launch_service_test.dart test/strong_alert_presentation_test.dart test/full_screen_alert_page_test.dart`

Expected: PASS；同 ID 原位更新、聚合文案、冷启动载荷和一次确认全部通过，页面源文件不含强提醒播放调用。

```powershell
git add -- mobile/android/app/src/main/java/org/codexnotif/mobile/MainActivity.java mobile/lib/main.dart mobile/lib/screens/full_screen_alert_page.dart mobile/lib/services/native_alert_launch_service.dart mobile/lib/services/strong_alert_presentation.dart mobile/test/native_alert_launch_service_test.dart mobile/test/strong_alert_presentation_test.dart mobile/test/full_screen_alert_page_test.dart
git commit -m "fix: 原位更新安卓全屏强提醒"
```

### Task 6: 全量回归、脱敏和小米真机验收

**Files:**
- Verify: `mobile/lib/**`
- Verify: `mobile/test/**`
- Verify: `mobile/android/**`
- Verify: `mobile/third_party/flutter_foreground_task/android/**`

**Interfaces:**
- Consumes: Tasks 1-5 的全部公开接口。
- Produces: 自动化测试、仓库审计和真机证据；不创建 Release。

- [ ] **Step 1: 运行格式化、静态分析和 Flutter 全量测试**

Run: `Set-Location mobile; dart format --set-exit-if-changed lib test`

Expected: exit `0`。

Run: `Set-Location mobile; flutter analyze`

Expected: `No issues found!`

Run: `Set-Location mobile; flutter test`

Expected: 所有测试 PASS。

- [ ] **Step 2: 运行原生插件测试和 Debug APK 构建**

Run: `Set-Location mobile/android; .\gradlew.bat :flutter_foreground_task:testDebugUnitTest`

Expected: `BUILD SUCCESSFUL`。

Run: `Set-Location mobile; flutter build apk --debug`

Expected: 生成 Debug APK；该文件保持未跟踪且不提交。

- [ ] **Step 3: 审计 Manifest、变更和敏感内容**

Run: `git diff --check 92698ca..HEAD`

Expected: 无空白错误。

Run: `git status --short`

Expected: APK、密钥和真实配置不在暂存区。

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\audit_public_repo.ps1 -Scope Worktree`

Expected: `PASS: no blocked public data`。

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\audit_public_repo.ps1 -Scope History`

Expected: `PASS: no blocked public data`；历史提交作者只使用项目公开的 noreply 身份。

- [ ] **Step 4: 安装到唯一已连接的小米设备**

```powershell
$deviceSerial = (adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice$" } | Select-Object -First 1).Split("`t")[0]
adb -s $deviceSerial install -r mobile\build\app\outputs\flutter-apk\app-debug.apk
```

Expected: `Success`。如果不是唯一一台在线设备，停止安装并先断开无关设备。

- [ ] **Step 5: 按单变量顺序执行真机验收**

1. 冷启动应用，开启监听，切到桌面但不划掉任务。
2. 触发一封匹配邮件；确认固定通知、所选铃声持续播放，并出现全屏页或系统横幅。
3. 不确认，再触发两封；确认只有一个通知，标题为“收到多封匹配邮件”，总数为 `3`，声音不中断、不从头重播。
4. 点击“我知道了”；确认声音立即停止、通知消失、页面关闭。
5. 再触发一封；确认新会话从 `count = 1` 开始。
6. 连接蓝牙 A2DP 设备，仅重复步骤 2 和 4；确认 Android 路由到当前活动输出设备。
7. 响铃时从最近任务划掉应用；确认服务和铃声停止，等待 60 秒不自动恢复。

每一步只改变一个条件。异常时先点击“我知道了”；按钮无效则执行 `adb shell am force-stop org.codexnotif.mobile` 紧急停止。

- [ ] **Step 6: 用系统证据确认行为**

```powershell
adb -s $deviceSerial shell dumpsys notification --noredact
adb -s $deviceSerial shell dumpsys activity services org.codexnotif.mobile
adb -s $deviceSerial logcat -d -s CodexNotifAudio CodexNotifAlert NotificationService flutter
```

Expected: 同一轮只有通知 ID `48202`；首次含全屏 PendingIntent，后续更新未重新响铃；日志只有播放器启动/停止和错误类型，不含 URI、邮箱、主题或正文；划掉后无前台服务且播放器已停止。

- [ ] **Step 7: 确认仓库最终状态**

Run: `git status --short`

Expected: 空输出。不得 push、打标签或上传 Release，直到用户再次明确授权。
