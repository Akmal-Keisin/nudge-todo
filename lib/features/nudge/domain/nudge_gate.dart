import '../../../core/platform/nudge_platform.dart';
import 'nudge_config.dart';

/// Decides whether a trigger should actually present the nudge, applying the
/// enabled flag, the pending-todo requirement, quiet hours and the cooldown.
class NudgeGate {
  const NudgeGate();

  bool shouldPresent({
    required NudgeTrigger trigger,
    required NudgeConfig config,
    required int pendingCount,
    required DateTime now,
    required DateTime? lastShownAt,
  }) {
    if (!config.enabled) return false;
    if (pendingCount == 0) return false;
    if (config.isWithinQuietHours(now)) return false;

    final bypassesCooldown =
        trigger == NudgeTrigger.boot || trigger == NudgeTrigger.login;
    if (bypassesCooldown) return true;

    if (lastShownAt == null) return true;
    final elapsed = now.difference(lastShownAt).inMinutes;
    return elapsed >= config.cooldownMinutes;
  }
}
