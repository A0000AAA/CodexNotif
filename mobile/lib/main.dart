import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'models/strong_alert.dart';
import 'screens/full_screen_alert_page.dart';
import 'screens/home_page.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();
  BackgroundService.initialize();
  await NotificationService.instance.initialize();

  runApp(const QqMailPagerApp());
}

class QqMailPagerApp extends StatefulWidget {
  const QqMailPagerApp({super.key});

  @override
  State<QqMailPagerApp> createState() => _QqMailPagerAppState();
}

class _QqMailPagerAppState extends State<QqMailPagerApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Set<int> _openAlertIds = <int>{};
  StreamSubscription<StrongAlert>? _strongAlertSubscription;

  @override
  void initState() {
    super.initState();
    _strongAlertSubscription =
        NotificationService.instance.strongAlerts.listen(_showStrongAlert);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.instance.takePendingStrongAlert();
      if (pending != null) _showStrongAlert(pending);
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _strongAlertSubscription?.cancel();
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data is! Map || data['type'] != 'strongAlert') return;
    final alert = StrongAlert.fromPayload(data['payload']?.toString());
    if (alert != null) _showStrongAlert(alert);
  }

  void _showStrongAlert(StrongAlert alert) {
    if (!_openAlertIds.add(alert.notificationId)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _openAlertIds.remove(alert.notificationId);
        return;
      }

      await navigator.push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FullScreenAlertPage(alert: alert),
        ),
      );
      _openAlertIds.remove(alert.notificationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'CodexNotif',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0A84FF),
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF121212) : scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
  );
}
