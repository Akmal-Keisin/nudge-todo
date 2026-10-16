enum NudgeTrigger { boot, login, unlock, screenOn, resume, manual }

class NudgeSnapshot {
  const NudgeSnapshot({
    required this.pendingCount,
    required this.titles,
    required this.enabled,
    required this.cooldownMinutes,
    required this.showTextInNotifications,
  });

  const NudgeSnapshot.empty()
    : pendingCount = 0,
      titles = const [],
      enabled = false,
      cooldownMinutes = 15,
      showTextInNotifications = true;

  final int pendingCount;
  final List<String> titles;
  final bool enabled;
  final int cooldownMinutes;
  final bool showTextInNotifications;
}

abstract class NudgePlatform {
  /// Wires up native listeners. Returns the trigger that launched the app, if
  /// any (Android only); later triggers arrive on [triggers].
  Future<NudgeTrigger?> initialize();

  /// State sync only: native keeps this so it can decide without starting
  /// Flutter. Must not surface anything to the user.
  Future<void> updateSnapshot(NudgeSnapshot snapshot);

  /// Surfaces the nudge now (notification and/or window). Only called once the
  /// cooldown and quiet-hours gate has already passed.
  Future<void> presentNudge(NudgeSnapshot snapshot);

  Future<void> setStartAtLogin(bool enabled);

  Stream<NudgeTrigger> get triggers;

  Future<void> dismiss();
}
