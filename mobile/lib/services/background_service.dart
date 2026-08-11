import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../background/mail_monitor_task.dart';
import '../models/monitor_health.dart';

class BackgroundStartResult {
  final bool success;
  final String message;

  const BackgroundStartResult(
    this.success,
    this.message,
  );
}

class BackgroundService {
  static void initialize() {
    /*
     * flutter_foreground_task 自带一个 5 秒 service state 检查：
     * startService -> checkServiceStateChange -> isRunningService
     *
     * 在当前小米/HyperOS 设备上，这个状态确认超时，但 Logcat
     * 没有 Android 系统拒绝/崩溃记录。
     *
     * 因此不让插件的 5 秒握手直接把启动请求判为失败。
     * 真正是否启动成功由：
     *   1. TaskHandler.onStart() 回报
     *   2. isRunningService 后续状态
     *   3. Android 常驻通知
     * 共同确认。
     */
    // Required on the target HyperOS device: the plugin's five-second state
    // handshake times out even though Android has started the service.
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterForegroundTask.skipServiceResponseCheck = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'qq_mail_monitor_service_v4',
        channelName: 'QQ 邮箱后台监听',
        channelDescription: '保持 QQ IMAP 连接；此常驻通知本身静默',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<void> requestRuntimePermissions() async {
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();

    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<BackgroundStartResult> startOrRestart() async {
    try {
      // 确保即使 initialize() 被调整过，这里也始终跳过插件 5 秒握手。
      // See initialize(): this is an intentional HyperOS compatibility path.
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterForegroundTask.skipServiceResponseCheck = true;

      final alreadyRunning = await FlutterForegroundTask.isRunningService;

      final ServiceRequestResult result;

      if (alreadyRunning) {
        result = await FlutterForegroundTask.restartService();
      } else {
        /*
         * 不再显式传 serviceTypes。
         *
         * AndroidManifest.xml 已经声明：
         * android:foregroundServiceType="specialUse"
         *
         * 这样与 flutter_foreground_task 官方示例一致，
         * 避免运行时重复覆盖 service type。
         */
        result = await FlutterForegroundTask.startService(
          serviceId: 48201,
          notificationTitle: 'QQ 邮箱提醒器正在监听',
          notificationText: '正在启动后台服务…',
          notificationIcon: null,
          callback: foregroundStartCallback,
        );
      }

      if (result is ServiceRequestFailure) {
        return BackgroundStartResult(
          false,
          'Android/插件启动调用本身失败：${result.error}',
        );
      }

      if (result is! ServiceRequestSuccess) {
        return BackgroundStartResult(
          false,
          '前台服务返回未知结果：$result',
        );
      }

      /*
       * skipServiceResponseCheck=true 后，ServiceRequestSuccess 只代表
       * platform startService 调用已成功提交，不代表 TaskHandler 已经启动。
       *
       * 给 Android/Flutter background isolate 一点时间。
       */
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(
          const Duration(milliseconds: 250),
        );

        if (await FlutterForegroundTask.isRunningService) {
          return const BackgroundStartResult(
            true,
            'Android 前台服务已确认运行，正在连接 QQ IMAP。',
          );
        }
      }

      /*
       * 此处不再错误地显示“系统拒绝”。
       * TaskHandler.onStart() 如果稍后起来，会主动发送 running=true 给 UI。
       */
      return const BackgroundStartResult(
        true,
        '启动请求已提交。正在等待后台 TaskHandler 回报；'
        '如果通知栏出现“QQ 邮箱提醒器正在监听”，说明 Android 前台服务已经运行。',
      );
    } catch (e, stack) {
      return BackgroundStartResult(
        false,
        '启动后台服务发生异常：$e\n$stack',
      );
    }
  }

  static Future<void> stop() async {
    try {
      // See initialize(): stopping must not hang on the same plugin handshake.
      // ignore: invalid_use_of_visible_for_testing_member
      FlutterForegroundTask.skipServiceResponseCheck = true;
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // 停止阶段不再因为 service response timeout 让 UI 崩溃。
    }
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  static Future<MonitorHealth> loadMonitorHealth() async {
    try {
      final epoch = await FlutterForegroundTask.getData(
        key: MonitorHealth.lastScanEpochKey,
      );
      final text = await FlutterForegroundTask.getData(
        key: MonitorHealth.lastScanTextKey,
      );
      final newMessageCount = await FlutterForegroundTask.getData(
        key: MonitorHealth.lastScanNewCountKey,
      );

      return MonitorHealth.fromStored(
        epochMilliseconds: _asInt(epoch),
        text: text?.toString(),
        newMessageCount: _asInt(newMessageCount),
      );
    } catch (_) {
      return const MonitorHealth();
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static void reload() {
    FlutterForegroundTask.sendDataToTask({
      'command': 'reload',
    });
  }
}
