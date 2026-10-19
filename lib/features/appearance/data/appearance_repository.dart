import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/appearance_settings.dart';

/// Persists [AppearanceSettings] as JSON alongside the other preferences.
class AppearanceRepository {
  AppearanceRepository(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _key = 'nudge_appearance';

  Future<AppearanceSettings> load() async {
    final json = await _prefs.getString(_key);
    if (json == null) return const AppearanceSettings();
    try {
      return AppearanceSettings.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      // A corrupted entry must not stop the app from starting.
      return const AppearanceSettings();
    }
  }

  Future<void> save(AppearanceSettings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
