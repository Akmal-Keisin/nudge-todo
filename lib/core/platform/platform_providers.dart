import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_nudge_platform.dart';
import 'linux_nudge_platform.dart';
import 'noop_nudge_platform.dart';
import 'nudge_platform.dart';

/// The only place in the app that reads [defaultTargetPlatform].
final targetPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

final nudgePlatformProvider = Provider<NudgePlatform>((ref) {
  final platform = switch (ref.watch(targetPlatformProvider)) {
    TargetPlatform.android => AndroidNudgePlatform(),
    TargetPlatform.linux => LinuxNudgePlatform(),
    _ => NoopNudgePlatform(),
  };
  // Tear down the stream controllers, D-Bus client and tray listener with the
  // provider instead of leaking them for the process lifetime.
  ref.onDispose(() => unawaited(platform.dispose()));
  return platform;
});
