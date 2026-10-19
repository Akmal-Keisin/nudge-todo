import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// Configures the native window on desktop. No-ops on platforms where
/// window_manager has no implementation (Android).
Future<void> setUpDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1080, 720),
      minimumSize: Size(420, 520),
      center: true,
      title: 'Nudge',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // Closing hides to the tray instead of quitting.
    await windowManager.setPreventClose(true);
  } catch (_) {
    // window_manager is unavailable (e.g. Android); nothing to configure.
  }
}
