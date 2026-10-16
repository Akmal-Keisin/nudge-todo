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
  return switch (ref.watch(targetPlatformProvider)) {
    TargetPlatform.android => AndroidNudgePlatform(),
    TargetPlatform.linux => LinuxNudgePlatform(),
    _ => NoopNudgePlatform(),
  };
});
