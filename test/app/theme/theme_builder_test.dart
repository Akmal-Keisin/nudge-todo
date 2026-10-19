import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/app/theme/theme_builder.dart';
import 'package:nudge/app/theme/theme_catalog.dart';
import 'package:nudge/features/appearance/domain/app_theme_id.dart';

void main() {
  test('builds a Material 3 theme from the selected scheme', () {
    final theme = buildThemeData(AppThemeId.ocean, Brightness.light);
    final scheme = colorSchemeFor(AppThemeId.ocean, Brightness.light);

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, scheme.primary);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
    expect(theme.cardTheme.color, scheme.surfaceContainerLow);
    expect(theme.appBarTheme.backgroundColor, scheme.surface);
    expect(theme.tabBarTheme.indicator, isA<BoxDecoration>());
  });

  test('cards use the shared rounded shape', () {
    final theme = buildThemeData(AppThemeId.forest, Brightness.dark);
    final shape = theme.cardTheme.shape;
    expect(shape, isA<RoundedRectangleBorder>());

    final borderRadius =
        (shape as RoundedRectangleBorder).borderRadius as BorderRadius;
    expect(borderRadius.topLeft, const Radius.circular(18));
  });

  test('light and dark differ', () {
    final light = buildThemeData(AppThemeId.grape, Brightness.light);
    final dark = buildThemeData(AppThemeId.grape, Brightness.dark);

    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
  });
}
