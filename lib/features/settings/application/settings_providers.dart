import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> save(ApiSettings settings) async {
    state = AsyncData(settings);
    await ref.read(apiSettingsRepositoryProvider).save(settings);
  }
}

final apiSettingsProvider =
    AsyncNotifierProvider<ApiSettingsController, ApiSettings>(
      ApiSettingsController.new,
    );
