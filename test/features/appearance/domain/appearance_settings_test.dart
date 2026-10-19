import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/appearance/domain/app_theme_id.dart';
import 'package:nudge/features/appearance/domain/appearance_settings.dart';

void main() {
  test('defaults to ocean and system', () {
    const settings = AppearanceSettings();
    expect(settings.theme, AppThemeId.ocean);
    expect(settings.mode, AppThemeMode.system);
  });

  test('round-trips through JSON', () {
    const settings = AppearanceSettings(
      theme: AppThemeId.grape,
      mode: AppThemeMode.dark,
    );
    final restored = AppearanceSettings.fromJson(settings.toJson());
    expect(restored.theme, AppThemeId.grape);
    expect(restored.mode, AppThemeMode.dark);
  });

  test('unknown values fall back to the defaults', () {
    final restored = AppearanceSettings.fromJson({
      'theme': 'neon',
      'mode': 'sepia',
    });
    expect(restored.theme, AppThemeId.ocean);
    expect(restored.mode, AppThemeMode.system);
  });

  test('missing values fall back to the defaults', () {
    final restored = AppearanceSettings.fromJson({});
    expect(restored.theme, AppThemeId.ocean);
    expect(restored.mode, AppThemeMode.system);
  });

  test('copyWith replaces one field at a time', () {
    const original = AppearanceSettings(
      theme: AppThemeId.forest,
      mode: AppThemeMode.light,
    );
    expect(original.copyWith(theme: AppThemeId.rose).mode, AppThemeMode.light);
    expect(original.copyWith(mode: AppThemeMode.dark).theme, AppThemeId.forest);
  });
}
