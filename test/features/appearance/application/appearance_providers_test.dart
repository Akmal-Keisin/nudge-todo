import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/appearance/application/appearance_providers.dart';
import 'package:nudge/features/appearance/data/appearance_repository.dart';
import 'package:nudge/features/appearance/domain/app_theme_id.dart';
import 'package:nudge/features/appearance/domain/appearance_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  ProviderContainer newContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('starts from the injected initial appearance', () {
    final container = ProviderContainer(
      overrides: [
        initialAppearanceProvider.overrideWithValue(
          const AppearanceSettings(
            theme: AppThemeId.midnight,
            mode: AppThemeMode.dark,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appearanceProvider).theme, AppThemeId.midnight);
    expect(container.read(appearanceProvider).mode, AppThemeMode.dark);
  });

  test('setTheme updates the state and persists it', () async {
    final container = newContainer();

    expect(
      await container
          .read(appearanceProvider.notifier)
          .setTheme(AppThemeId.forest),
      isNull,
    );
    expect(container.read(appearanceProvider).theme, AppThemeId.forest);

    final saved = await AppearanceRepository(SharedPreferencesAsync()).load();
    expect(saved.theme, AppThemeId.forest);
  });

  test('setMode updates the state and persists it', () async {
    final container = newContainer();

    expect(
      await container
          .read(appearanceProvider.notifier)
          .setMode(AppThemeMode.dark),
      isNull,
    );
    expect(container.read(appearanceProvider).mode, AppThemeMode.dark);

    final saved = await AppearanceRepository(SharedPreferencesAsync()).load();
    expect(saved.mode, AppThemeMode.dark);
  });
}
