import 'package:flutter/material.dart';

import '../../features/appearance/domain/app_theme_id.dart';

/// One selectable palette. The colors are derived from [seed] with [variant],
/// so light and dark stay in step without hand-writing every token.
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.seed,
    required this.variant,
  });

  final AppThemeId id;
  final String label;
  final Color seed;
  final DynamicSchemeVariant variant;
}

const themePresets = <ThemePreset>[
  ThemePreset(
    id: AppThemeId.ocean,
    label: 'Ocean',
    seed: Color(0xFF00639B),
    variant: DynamicSchemeVariant.fidelity,
  ),
  ThemePreset(
    id: AppThemeId.sunset,
    label: 'Sunset',
    seed: Color(0xFFD84315),
    variant: DynamicSchemeVariant.vibrant,
  ),
  ThemePreset(
    id: AppThemeId.forest,
    label: 'Forest',
    seed: Color(0xFF2E7D32),
    variant: DynamicSchemeVariant.fidelity,
  ),
  ThemePreset(
    id: AppThemeId.grape,
    label: 'Grape',
    seed: Color(0xFF6A1B9A),
    variant: DynamicSchemeVariant.expressive,
  ),
  ThemePreset(
    id: AppThemeId.rose,
    label: 'Rose',
    seed: Color(0xFFAD1457),
    variant: DynamicSchemeVariant.vibrant,
  ),
  ThemePreset(
    id: AppThemeId.midnight,
    label: 'Midnight',
    seed: Color(0xFF1A237E),
    variant: DynamicSchemeVariant.vibrant,
  ),
];

ThemePreset presetFor(AppThemeId id) {
  for (final preset in themePresets) {
    if (preset.id == id) return preset;
  }
  // Every enum value has a preset; this keeps the function total if one is
  // ever added without a catalog entry.
  return themePresets.first;
}

/// `ColorScheme.fromSeed` computes full tonal palettes, so the result is cached
/// per preset and brightness rather than rebuilt on every frame.
final _schemeCache = <String, ColorScheme>{};

ColorScheme colorSchemeFor(AppThemeId id, Brightness brightness) {
  final key = '${id.name}-${brightness.name}';
  return _schemeCache.putIfAbsent(key, () {
    final preset = presetFor(id);
    return ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: brightness,
      dynamicSchemeVariant: preset.variant,
    );
  });
}

/// Preview colors for the picker, taken from the real light scheme so the
/// swatches can never drift from the applied theme.
List<Color> previewSwatches(AppThemeId id) {
  final scheme = colorSchemeFor(id, Brightness.light);
  return [scheme.primary, scheme.secondaryContainer, scheme.tertiaryContainer];
}
