import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/app/theme/theme_catalog.dart';
import 'package:nudge/features/appearance/domain/app_theme_id.dart';

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every preset builds a scheme for both brightnesses', () {
    for (final preset in themePresets) {
      for (final brightness in Brightness.values) {
        final scheme = colorSchemeFor(preset.id, brightness);
        expect(
          scheme.brightness,
          brightness,
          reason: '${preset.id.name} ${brightness.name}',
        );
      }
    }
  });

  test('ids and labels are unique and cover every enum value', () {
    expect(
      themePresets.map((preset) => preset.id).toSet(),
      AppThemeId.values.toSet(),
    );
    expect(
      themePresets.map((preset) => preset.label).toSet(),
      hasLength(themePresets.length),
    );
  });

  test('every preset keeps text and on-primary contrast readable', () {
    for (final preset in themePresets) {
      for (final brightness in Brightness.values) {
        final scheme = colorSchemeFor(preset.id, brightness);
        final name = '${preset.label} ${brightness.name}';
        expect(
          _contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name surface',
        );
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: '$name primary',
        );
      }
    }
  });

  test('preview swatches come from the real light scheme', () {
    final scheme = colorSchemeFor(AppThemeId.rose, Brightness.light);
    expect(previewSwatches(AppThemeId.rose), [
      scheme.primary,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ]);
  });
}
