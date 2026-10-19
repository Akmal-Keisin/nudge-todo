import 'app_theme_id.dart';

/// The user's appearance choice, persisted as JSON.
class AppearanceSettings {
  const AppearanceSettings({
    this.theme = AppThemeId.ocean,
    this.mode = AppThemeMode.system,
  });

  final AppThemeId theme;
  final AppThemeMode mode;

  AppearanceSettings copyWith({AppThemeId? theme, AppThemeMode? mode}) {
    return AppearanceSettings(
      theme: theme ?? this.theme,
      mode: mode ?? this.mode,
    );
  }

  Map<String, dynamic> toJson() => {'theme': theme.name, 'mode': mode.name};

  /// Unknown or missing values fall back to the defaults, so an entry written
  /// by a newer build (or a renamed preset) never breaks startup.
  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      theme: _themeFrom(json['theme']),
      mode: _modeFrom(json['mode']),
    );
  }

  static AppThemeId _themeFrom(Object? raw) {
    for (final theme in AppThemeId.values) {
      if (theme.name == raw) return theme;
    }
    return AppThemeId.ocean;
  }

  static AppThemeMode _modeFrom(Object? raw) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return AppThemeMode.system;
  }
}
