import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/nudge_config.dart';

class NudgeSettingsRepository {
  NudgeSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _key = 'nudge_config';
  static const _lastNudgeKey = 'nudge_last_shown_at';

  Future<NudgeConfig> load() async {
    final json = await _prefs.getString(_key);
    if (json == null) return const NudgeConfig();
    return NudgeConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> save(NudgeConfig config) async {
    await _prefs.setString(_key, jsonEncode(config.toJson()));
  }

  Future<DateTime?> loadLastShownAt() async {
    final value = await _prefs.getString(_lastNudgeKey);
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> saveLastShownAt(DateTime at) async {
    await _prefs.setString(_lastNudgeKey, at.toUtc().toIso8601String());
  }
}
