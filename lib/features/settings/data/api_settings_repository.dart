import 'package:shared_preferences/shared_preferences.dart';

import '../domain/api_settings.dart';
import 'token_store.dart';

/// Persists [ApiSettings]: the URL with the other preferences, the token in
/// secure storage.
class ApiSettingsRepository {
  ApiSettingsRepository(this._prefs, this._tokens);

  final SharedPreferencesAsync _prefs;
  final TokenStore _tokens;

  static const _urlKey = 'nudge_api_base_url';

  Future<ApiSettings> load() async {
    // The secure-storage read can be slow (keyring/libsecret), so run it
    // alongside the preferences read rather than after it.
    final results = await Future.wait([
      _prefs.getString(_urlKey),
      _tokens.read(),
    ]);
    final url = results[0] ?? '';
    final token = results[1] ?? '';
    return ApiSettings(baseUrl: url, token: token);
  }

  Future<void> save(ApiSettings settings) async {
    await _prefs.setString(_urlKey, settings.baseUrl.trim());
    if (settings.token.isEmpty) {
      await _tokens.clear();
    } else {
      await _tokens.write(settings.token);
    }
  }
}
