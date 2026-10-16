// The tray_manager 0.5.x API is deprecated in favour of its FFI-based native
// API, but the package's own example still targets the legacy API and there is
// no published migration guide yet. Keep the simpler API for now.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'nudge_platform.dart';

class LinuxNudgePlatform
    with TrayListener, WindowListener
    implements NudgePlatform {
  LinuxNudgePlatform();

  static const _appName = 'Nudge';
  static const _notificationId = 1;

  final _controller = StreamController<NudgeTrigger>.broadcast();
  final _notifications = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  DBusClient? _dbusClient;
  NudgeSnapshot _snapshot = const NudgeSnapshot.empty();
  String? _trayIconPath;

  @override
  Stream<NudgeTrigger> get triggers => _controller.stream;

  @override
  Future<NudgeTrigger?> initialize() async {
    await _initNotifications();
    await _initTray();
    launchAtStartup.setup(
      appName: _appName,
      appPath: Platform.resolvedExecutable,
    );
    windowManager.addListener(this);
    await _listenForLoginSignals();
    return null;
  }

  Future<void> _initNotifications() async {
    const settings = InitializationSettings(
      linux: LinuxInitializationSettings(defaultActionName: 'Open Nudge'),
    );
    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _showWindow();
        _controller.add(NudgeTrigger.manual);
      },
    );
  }

  Future<void> _initTray() async {
    try {
      _trayIconPath = await _materializeAsset('assets/tray_icon.png');
      if (_trayIconPath != null) {
        await trayManager.setIcon(_trayIconPath!);
      }
      trayManager.addListener(this);
      await _refreshTrayMenu();
    } catch (_) {
      // No StatusNotifierItem host (e.g. no Waybar/Noctalia tray). The app
      // still runs; the tray is simply unavailable.
    }
  }

  Future<String?> _materializeAsset(String assetKey) async {
    final dir = Directory('${Directory.systemTemp.path}/nudge');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/${assetKey.split('/').last}');
    if (!file.existsSync()) {
      final ByteData data = await rootBundle.load(assetKey);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return file.path;
  }

  Future<void> _refreshTrayMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Nudge'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
    await trayManager.setToolTip(_tooltip());
  }

  String _tooltip() {
    if (!_snapshot.enabled) return 'Nudge (off)';
    if (_snapshot.pendingCount == 0) return 'Nudge - all clear';
    return 'Nudge - ${_snapshot.pendingCount} pending';
  }

  Future<void> _listenForLoginSignals() async {
    try {
      final client = DBusClient.system();
      _dbusClient = client;

      final session = DBusRemoteObject(
        client,
        name: 'org.freedesktop.login1',
        path: DBusObjectPath('/org/freedesktop/login1/session/auto'),
      );
      _subscriptions.add(
        DBusRemoteObjectSignalStream(
          object: session,
          interface: 'org.freedesktop.login1.Session',
          name: 'Unlock',
        ).listen((_) => _controller.add(NudgeTrigger.unlock)),
      );

      final manager = DBusRemoteObject(
        client,
        name: 'org.freedesktop.login1',
        path: DBusObjectPath('/org/freedesktop/login1'),
      );
      _subscriptions.add(
        DBusRemoteObjectSignalStream(
          object: manager,
          interface: 'org.freedesktop.login1.Manager',
          name: 'PrepareForSleep',
        ).listen((signal) {
          final sleeping =
              signal.values.isNotEmpty && signal.values.first.asBoolean();
          if (!sleeping) _controller.add(NudgeTrigger.resume);
        }),
      );
    } catch (_) {
      // logind unavailable (e.g. non-systemd). Triggers degrade to manual
      // refresh and the tray menu.
    }
  }

  Future<void> _showWindow() async {
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    await windowManager.focus();
  }

  @override
  Future<void> updateSnapshot(NudgeSnapshot snapshot) async {
    _snapshot = snapshot;
    try {
      await trayManager.setToolTip(_tooltip());
    } catch (_) {}
  }

  @override
  Future<void> presentNudge(NudgeSnapshot snapshot) async {
    _snapshot = snapshot;
    // Best effort: on niri a window raised from the background is marked
    // urgent rather than focused, so the notification is what reaches the user.
    try {
      if (!await windowManager.isVisible()) {
        await windowManager.show();
      }
    } catch (_) {}
    await _showNotification();
  }

  Future<void> _showNotification() async {
    final body =
        _snapshot.showTextInNotifications && _snapshot.titles.isNotEmpty
        ? _snapshot.titles.take(5).join('\n')
        : 'Open Nudge to see your list.';
    final noun = _snapshot.pendingCount == 1 ? 'thing' : 'things';

    try {
      await _notifications.show(
        id: _notificationId,
        title: 'You have ${_snapshot.pendingCount} $noun to do',
        body: body,
        notificationDetails: const NotificationDetails(
          linux: LinuxNotificationDetails(
            urgency: LinuxNotificationUrgency.normal,
          ),
        ),
      );
    } catch (_) {
      // The notification daemon may be unavailable; the window and tray still
      // work, so a failed notification is not fatal.
    }
  }

  @override
  Future<void> setStartAtLogin(bool enabled) async {
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (_) {}
  }

  @override
  Future<void> dismiss() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
    _controller.add(NudgeTrigger.manual);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        _controller.add(NudgeTrigger.manual);
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  void onWindowClose() {
    // "X" hides to the tray; the app keeps running to receive triggers.
    windowManager.hide();
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _dbusClient?.close();
    trayManager.removeListener(this);
    await _controller.close();
  }
}
