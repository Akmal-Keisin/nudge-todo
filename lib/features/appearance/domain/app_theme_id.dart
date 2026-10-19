/// The selectable palettes. Kept Flutter-free so the domain layer stays pure
/// Dart; the actual colors live in `app/theme/theme_catalog.dart`.
enum AppThemeId { ocean, sunset, forest, grape, rose, midnight }

/// Light/dark preference. Our own enum rather than Flutter's `ThemeMode`, again
/// to keep the domain Flutter-free; the app layer maps it.
enum AppThemeMode { system, light, dark }
