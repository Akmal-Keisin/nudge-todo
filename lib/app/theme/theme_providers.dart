import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/appearance/application/appearance_providers.dart';
import 'theme_builder.dart';

/// Built only when the selected preset changes: a mode-only change does not
/// need to recompute either palette.
final lightThemeProvider = Provider<ThemeData>((ref) {
  final id = ref.watch(appearanceProvider.select((settings) => settings.theme));
  return buildThemeData(id, Brightness.light);
});

final darkThemeProvider = Provider<ThemeData>((ref) {
  final id = ref.watch(appearanceProvider.select((settings) => settings.theme));
  return buildThemeData(id, Brightness.dark);
});
