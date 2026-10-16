import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/nudge/domain/nudge_config.dart';

void main() {
  group('isWithinQuietHours', () {
    test('is false when disabled', () {
      const config = NudgeConfig(
        quietHoursEnabled: false,
        quietHoursStartMinutes: 22 * 60,
        quietHoursEndMinutes: 7 * 60,
      );
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 23)), isFalse);
    });

    test('handles a window that crosses midnight', () {
      const config = NudgeConfig(
        quietHoursEnabled: true,
        quietHoursStartMinutes: 22 * 60,
        quietHoursEndMinutes: 7 * 60,
      );
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 23)), isTrue);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 3)), isTrue);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 6, 59)), isTrue);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 7)), isFalse);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 12)), isFalse);
      expect(
        config.isWithinQuietHours(DateTime(2026, 10, 15, 21, 59)),
        isFalse,
      );
    });

    test('handles a same-day window', () {
      const config = NudgeConfig(
        quietHoursEnabled: true,
        quietHoursStartMinutes: 9 * 60,
        quietHoursEndMinutes: 17 * 60,
      );
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 12)), isTrue);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 8, 59)), isFalse);
      expect(config.isWithinQuietHours(DateTime(2026, 10, 15, 17)), isFalse);
    });
  });

  test('round-trips through JSON', () {
    const config = NudgeConfig(
      enabled: false,
      cooldownMinutes: 42,
      quietHoursEnabled: true,
      quietHoursStartMinutes: 1000,
      quietHoursEndMinutes: 200,
      startAtLogin: false,
      showTextInNotifications: false,
    );
    final restored = NudgeConfig.fromJson(config.toJson());
    expect(restored.enabled, isFalse);
    expect(restored.cooldownMinutes, 42);
    expect(restored.quietHoursEnabled, isTrue);
    expect(restored.quietHoursStartMinutes, 1000);
    expect(restored.quietHoursEndMinutes, 200);
    expect(restored.startAtLogin, isFalse);
    expect(restored.showTextInNotifications, isFalse);
  });
}
