import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/nudge_app.dart';
import 'core/platform/window_setup.dart';
import 'features/appearance/application/appearance_providers.dart';
import 'features/appearance/data/appearance_repository.dart';
import 'features/appearance/domain/appearance_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpDesktopWindow();

  // Read the saved appearance before the first frame so the app starts in the
  // chosen theme instead of flashing the default palette.
  final appearance = await _loadAppearance();

  runApp(
    ProviderScope(
      overrides: [initialAppearanceProvider.overrideWithValue(appearance)],
      child: const NudgeApp(),
    ),
  );
}

Future<AppearanceSettings> _loadAppearance() async {
  try {
    return await AppearanceRepository(SharedPreferencesAsync()).load();
  } catch (_) {
    // A preferences failure must not stop the app from starting; fall back to
    // the default palette and let the rest of the app surface storage errors.
    return const AppearanceSettings();
  }
}
