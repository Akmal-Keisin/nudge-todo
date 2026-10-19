import 'dart:async';

import 'nudge_platform.dart';

class NoopNudgePlatform implements NudgePlatform {
  final _controller = StreamController<NudgeTrigger>.broadcast();

  @override
  Stream<NudgeTrigger> get triggers => _controller.stream;

  @override
  Future<NudgeTrigger?> initialize() async => null;

  @override
  Future<void> updateSnapshot(NudgeSnapshot snapshot) async {}

  @override
  Future<void> presentNudge(NudgeSnapshot snapshot) async {}

  @override
  Future<void> setStartAtLogin(bool enabled) async {}

  @override
  Future<void> dismiss() async {}

  @override
  Future<void> dispose() => _controller.close();
}
