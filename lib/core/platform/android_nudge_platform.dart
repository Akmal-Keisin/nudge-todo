import 'dart:async';

import 'package:flutter/services.dart';

import 'nudge_platform.dart';

class AndroidNudgePlatform implements NudgePlatform {
  AndroidNudgePlatform();

  static const _method = MethodChannel('com.nudge/nudge');
  static const _events = EventChannel('com.nudge/nudge_events');

  final _controller = StreamController<NudgeTrigger>.broadcast();
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<NudgeTrigger> get triggers => _controller.stream;

  @override
  Future<NudgeTrigger?> initialize() async {
    _sub = _events.receiveBroadcastStream().listen((event) {
      final trigger = _parseTrigger(event as String?);
      if (trigger != null) _controller.add(trigger);
    });

    final initial = await _method.invokeMethod<String>('getInitialTrigger');
    return _parseTrigger(initial);
  }

  NudgeTrigger? _parseTrigger(String? value) {
    return switch (value) {
      'boot' => NudgeTrigger.boot,
      'unlock' => NudgeTrigger.unlock,
      'screenOn' => NudgeTrigger.screenOn,
      _ => null,
    };
  }

  @override
  Future<void> updateSnapshot(NudgeSnapshot snapshot) async {
    await _method.invokeMethod<void>('updateSnapshot', {
      'pendingCount': snapshot.pendingCount,
      'titles': snapshot.titles,
      'enabled': snapshot.enabled,
      'cooldownMinutes': snapshot.cooldownMinutes,
      'showTextInNotifications': snapshot.showTextInNotifications,
    });
  }

  @override
  Future<void> presentNudge(NudgeSnapshot snapshot) async {
    await _method.invokeMethod<void>('presentNudge', {
      'pendingCount': snapshot.pendingCount,
      'titles': snapshot.titles,
      'enabled': snapshot.enabled,
      'cooldownMinutes': snapshot.cooldownMinutes,
      'showTextInNotifications': snapshot.showTextInNotifications,
    });
  }

  @override
  Future<void> setStartAtLogin(bool enabled) async {
    await _method.invokeMethod<void>('setStartAtLogin', {'enabled': enabled});
  }

  @override
  Future<void> dismiss() async {
    await _method.invokeMethod<void>('dismiss');
  }

  Future<bool> isHyperOs() async {
    final result = await _method.invokeMethod<bool>('isHyperOs');
    return result ?? false;
  }

  Future<void> openAutostartSettings() async {
    await _method.invokeMethod<void>('openAutostartSettings');
  }

  Future<void> openBatterySettings() async {
    await _method.invokeMethod<void>('openBatterySettings');
  }

  Future<void> requestNotificationPermission() async {
    await _method.invokeMethod<void>('requestNotificationPermission');
  }

  Future<void> requestFullScreenIntentPermission() async {
    await _method.invokeMethod<void>('requestFullScreenIntentPermission');
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
