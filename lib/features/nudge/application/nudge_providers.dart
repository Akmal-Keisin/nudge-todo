import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/nudge_platform.dart';
import '../../../core/platform/platform_providers.dart';
import '../../../core/storage/storage_providers.dart';
import '../../todos/application/todo_providers.dart';
import '../data/nudge_settings_repository.dart';
import '../domain/nudge_config.dart';
import '../domain/nudge_gate.dart';
import 'nudge_snapshot.dart';

final nudgeSettingsRepositoryProvider = Provider<NudgeSettingsRepository>((
  ref,
) {
  return NudgeSettingsRepository(ref.watch(sharedPreferencesProvider));
});

class NudgeConfigController extends AsyncNotifier<NudgeConfig> {
  @override
  Future<NudgeConfig> build() {
    return ref.watch(nudgeSettingsRepositoryProvider).load();
  }

  Future<void> save(NudgeConfig config) async {
    state = AsyncData(config);
    await ref.read(nudgeSettingsRepositoryProvider).save(config);
    await ref.read(nudgePlatformProvider).setStartAtLogin(config.startAtLogin);
  }
}

final nudgeConfigProvider =
    AsyncNotifierProvider<NudgeConfigController, NudgeConfig>(
      NudgeConfigController.new,
    );

class NudgeBannerController extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;

  void hide() => state = false;
}

final nudgeBannerProvider = NotifierProvider<NudgeBannerController, bool>(
  NudgeBannerController.new,
);

final nudgeTriggerProvider = StreamProvider<NudgeTrigger>((ref) {
  return ref.watch(nudgePlatformProvider).triggers;
});

final nudgeGateProvider = Provider<NudgeGate>((ref) => const NudgeGate());

/// Applies the gate and, when it passes, surfaces the nudge (notification or
/// window) and raises the in-app banner.
class NudgeCoordinator {
  NudgeCoordinator(this._ref);

  final Ref _ref;

  Future<void> handleTrigger(NudgeTrigger trigger) async {
    final config = await _ref.read(nudgeConfigProvider.future);
    final todos = await _ref.read(todoListProvider.future);
    final snapshot = buildNudgeSnapshot(config: config, todos: todos);

    final repo = _ref.read(nudgeSettingsRepositoryProvider);
    final lastShownAt = await repo.loadLastShownAt();
    final now = DateTime.now().toUtc();

    final shouldShow = _ref
        .read(nudgeGateProvider)
        .shouldPresent(
          trigger: trigger,
          config: config,
          pendingCount: snapshot.pendingCount,
          now: now,
          lastShownAt: lastShownAt,
        );

    if (!shouldShow) return;

    await repo.saveLastShownAt(now);
    await _ref.read(nudgePlatformProvider).presentNudge(snapshot);
    _ref.read(nudgeBannerProvider.notifier).show();
  }
}

final nudgeCoordinatorProvider = Provider<NudgeCoordinator>(
  NudgeCoordinator.new,
);
