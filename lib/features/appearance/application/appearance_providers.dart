import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/appearance_repository.dart';
import '../domain/app_theme_id.dart';
import '../domain/appearance_settings.dart';

final appearanceRepositoryProvider = Provider<AppearanceRepository>((ref) {
  return AppearanceRepository(ref.watch(sharedPreferencesProvider));
});

/// The saved value, read in `main` before `runApp` and overridden there, so the
/// first frame already uses the chosen theme instead of flashing the default.
final initialAppearanceProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
);

class AppearanceController extends Notifier<AppearanceSettings> {
  @override
  AppearanceSettings build() => ref.watch(initialAppearanceProvider);

  Future<AppFailure?> setTheme(AppThemeId theme) {
    return _save(state.copyWith(theme: theme));
  }

  Future<AppFailure?> setMode(AppThemeMode mode) {
    return _save(state.copyWith(mode: mode));
  }

  /// Applies the change optimistically and reverts it if the write fails, so
  /// the UI never claims a preference was saved when it was not.
  Future<AppFailure?> _save(AppearanceSettings next) async {
    final previous = state;
    state = next;
    try {
      await ref.read(appearanceRepositoryProvider).save(next);
      return null;
    } catch (_) {
      state = previous;
      return const StorageFailure();
    }
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceSettings>(
      AppearanceController.new,
    );
