import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/api_settings_repository.dart';
import '../data/token_store.dart';
import '../domain/api_settings.dart';

/// Overridden in tests with [InMemoryTokenStore].
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiSettingsRepositoryProvider = Provider<ApiSettingsRepository>((ref) {
  return ApiSettingsRepository(
    ref.watch(sharedPreferencesProvider),
    ref.watch(tokenStoreProvider),
  );
});

class ApiSettingsController extends AsyncNotifier<ApiSettings> {
  @override
  Future<ApiSettings> build() {
    return ref.watch(apiSettingsRepositoryProvider).load();
  }

  /// Applies [settings] optimistically, reverting on a storage failure and
  /// returning it so the caller can show a message.
  Future<AppFailure?> save(ApiSettings settings) async {
    final previous = state.value;
    state = AsyncData(settings);
    try {
      await ref.read(apiSettingsRepositoryProvider).save(settings);
      return null;
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      return const StorageFailure();
    }
  }
}

final apiSettingsProvider =
    AsyncNotifierProvider<ApiSettingsController, ApiSettings>(
      ApiSettingsController.new,
    );
