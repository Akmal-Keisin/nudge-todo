import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/platform/nudge_platform.dart';
import 'package:nudge/features/nudge/domain/nudge_config.dart';
import 'package:nudge/features/nudge/domain/nudge_gate.dart';

void main() {
  const gate = NudgeGate();
  final now = DateTime.utc(2026, 10, 15, 12, 0);

  bool present({
    required NudgeTrigger trigger,
    NudgeConfig config = const NudgeConfig(),
    int pendingCount = 1,
    DateTime? lastShownAt,
  }) {
    return gate.shouldPresent(
      trigger: trigger,
      config: config,
      pendingCount: pendingCount,
      now: now,
      lastShownAt: lastShownAt,
    );
  }

  test('does not present when disabled', () {
    expect(
      present(
        trigger: NudgeTrigger.unlock,
        config: const NudgeConfig(enabled: false),
      ),
      isFalse,
    );
  });

  test('does not present with no pending todos', () {
    expect(present(trigger: NudgeTrigger.unlock, pendingCount: 0), isFalse);
  });

  test('does not present during quiet hours', () {
    expect(
      present(
        trigger: NudgeTrigger.unlock,
        config: const NudgeConfig(
          quietHoursEnabled: true,
          quietHoursStartMinutes: 11 * 60,
          quietHoursEndMinutes: 13 * 60,
        ),
      ),
      isFalse,
    );
  });

  test('boot and login ignore the cooldown', () {
    final lastShown = now.subtract(const Duration(minutes: 1));
    expect(present(trigger: NudgeTrigger.boot, lastShownAt: lastShown), isTrue);
    expect(
      present(trigger: NudgeTrigger.login, lastShownAt: lastShown),
      isTrue,
    );
  });

  test('unlock respects the cooldown', () {
    final lastShown = now.subtract(const Duration(minutes: 5));
    expect(
      present(trigger: NudgeTrigger.unlock, lastShownAt: lastShown),
      isFalse,
    );
    expect(
      present(
        trigger: NudgeTrigger.unlock,
        lastShownAt: now.subtract(const Duration(minutes: 20)),
      ),
      isTrue,
    );
  });

  test('presents on first run with no previous nudge', () {
    expect(present(trigger: NudgeTrigger.unlock), isTrue);
  });
}
