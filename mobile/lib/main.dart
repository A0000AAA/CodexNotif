import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'models/strong_alert.dart';
import 'screens/full_screen_alert_page.dart';
import 'screens/home_page.dart';
import 'services/background_service.dart';
import 'services/native_alert_launch_service.dart';
import 'services/notification_service.dart';
import 'services/strong_alert_presentation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();
  BackgroundService.initialize();
  await NativeAlertLaunchService.instance.initialize();
  await NotificationService.instance.initialize();

  runApp(const QqMailPagerApp());
}

class QqMailPagerApp extends StatefulWidget {
  const QqMailPagerApp({
    super.key,
    this.notificationAlerts,
    this.home,
  });

  final Stream<StrongAlert>? notificationAlerts;
  final Widget? home;

  @override
  State<QqMailPagerApp> createState() => _QqMailPagerAppState();
}

class _QqMailPagerAppState extends State<QqMailPagerApp> {
  static const _acknowledgedTokenTtl = Duration(minutes: 10);
  static const _maxAcknowledgedTokens = 128;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final StrongAlertPresentation _presentation = StrongAlertPresentation();
  final Map<String, _OpenStrongAlertRoute> _openRoutes = {};
  final Map<String, DateTime> _acknowledgedTokens = {};
  StreamSubscription<StrongAlert>? _strongAlertSubscription;
  StreamSubscription<StrongAlert>? _nativeAlertSubscription;

  @override
  void initState() {
    super.initState();
    _strongAlertSubscription =
        (widget.notificationAlerts ?? NotificationService.instance.strongAlerts)
            .listen(_showStrongAlert);
    _nativeAlertSubscription =
        NativeAlertLaunchService.instance.alerts.listen(_showStrongAlert);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    final pending = NotificationService.instance.takePendingStrongAlert();
    if (pending != null) _showStrongAlert(pending);
    final nativePending = NativeAlertLaunchService.instance.takePending();
    if (nativePending != null) _showStrongAlert(nativePending);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _strongAlertSubscription?.cancel();
    _nativeAlertSubscription?.cancel();
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['type']) {
      case 'strongAlert':
        final alert = StrongAlert.fromPayload(data['payload']?.toString());
        if (alert != null) _showStrongAlert(alert);
      case 'strongAlertAcknowledged':
        final notificationId = switch (data['notificationId']) {
          final int value => value,
          final Object value => int.tryParse(value.toString()),
          _ => null,
        };
        final sessionToken = data['sessionToken']?.toString() ?? '';
        if (notificationId != null) {
          _removeAcknowledgedRoute(notificationId, sessionToken);
        }
    }
  }

  void _showStrongAlert(StrongAlert alert) {
    if (_isAcknowledged(alert.sessionToken)) return;
    final update = _presentation.openOrUpdate(alert);
    if (!update.created) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_isAcknowledged(alert.sessionToken)) {
        _presentation
            .remove(alert.sessionToken, expected: update.listenable)
            ?.dispose();
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (!mounted || navigator == null) {
        _presentation
            .remove(alert.sessionToken, expected: update.listenable)
            ?.dispose();
        return;
      }

      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FullScreenAlertPage(
          alertListenable: update.listenable,
        ),
      );
      final open = _OpenStrongAlertRoute(route, update.listenable);
      _openRoutes[alert.sessionToken] = open;
      await navigator.push<void>(route);
      if (identical(_openRoutes[alert.sessionToken], open)) {
        _openRoutes.remove(alert.sessionToken);
      }
      _presentation
          .remove(alert.sessionToken, expected: update.listenable)
          ?.dispose();
    });
  }

  void _removeAcknowledgedRoute(int notificationId, String sessionToken) {
    final open = _openRoutes[sessionToken];
    final listenable = open?.listenable ?? _presentation.find(sessionToken);
    if (listenable == null ||
        listenable.value.notificationId != notificationId ||
        listenable.value.sessionToken != sessionToken) {
      return;
    }
    _rememberAcknowledged(sessionToken);
    if (open == null) return;

    _openRoutes.remove(sessionToken);
    _navigatorKey.currentState?.removeRoute(open.route);
    _presentation.remove(sessionToken, expected: open.listenable)?.dispose();
  }

  bool _isAcknowledged(String sessionToken) {
    _pruneAcknowledgedTokens(DateTime.now().toUtc());
    return _acknowledgedTokens.containsKey(sessionToken);
  }

  void _rememberAcknowledged(String sessionToken) {
    final now = DateTime.now().toUtc();
    _pruneAcknowledgedTokens(now);
    _acknowledgedTokens.remove(sessionToken);
    _acknowledgedTokens[sessionToken] = now;
    while (_acknowledgedTokens.length > _maxAcknowledgedTokens) {
      _acknowledgedTokens.remove(_acknowledgedTokens.keys.first);
    }
  }

  void _pruneAcknowledgedTokens(DateTime now) {
    _acknowledgedTokens.removeWhere(
      (_, acknowledgedAt) =>
          now.difference(acknowledgedAt) >= _acknowledgedTokenTtl,
    );
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
      home: widget.home ?? const HomePage(),
    );
  }
}

class _OpenStrongAlertRoute {
  const _OpenStrongAlertRoute(this.route, this.listenable);

  final Route<void> route;
  final ValueNotifier<StrongAlert> listenable;
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
