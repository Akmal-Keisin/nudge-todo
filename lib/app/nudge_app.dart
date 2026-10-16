import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/platform_providers.dart';
import '../features/nudge/application/nudge_providers.dart';
import '../features/nudge/application/nudge_snapshot.dart';
import '../features/todos/application/todo_providers.dart';
import '../features/todos/presentation/todo_list_screen.dart';

class NudgeApp extends ConsumerStatefulWidget {
  const NudgeApp({super.key});

  @override
  ConsumerState<NudgeApp> createState() => _NudgeAppState();
}

class _NudgeAppState extends ConsumerState<NudgeApp> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    // Listeners below can fire before initialize() finishes (the config and
    // list load fast; the platform setup does D-Bus and tray work), so gate
    // every snapshot push behind this future.
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    final platform = ref.read(nudgePlatformProvider);
    final initial = await platform.initialize();

    // Apply the stored start-at-login preference on every launch so the
    // autostart entry exists even on a fresh install.
    final config = await ref.read(nudgeConfigProvider.future);
    await platform.setStartAtLogin(config.startAtLogin);

    if (initial != null) {
      await ref.read(nudgeCoordinatorProvider).handleTrigger(initial);
    }
    _pushSnapshotNow();
  }

  Future<void> _pushSnapshot() async {
    await _ready;
    _pushSnapshotNow();
  }

  void _pushSnapshotNow() {
    final config = ref.read(nudgeConfigProvider).value;
    if (config == null) return;

    final todos = ref.read(todoListProvider).value ?? const [];
    ref
        .read(nudgePlatformProvider)
        .updateSnapshot(buildNudgeSnapshot(config: config, todos: todos));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(nudgeTriggerProvider, (previous, next) {
      final trigger = next.value;
      if (trigger != null) {
        ref.read(nudgeCoordinatorProvider).handleTrigger(trigger);
      }
    });
    ref.listen(todoListProvider, (previous, next) => _pushSnapshot());
    ref.listen(nudgeConfigProvider, (previous, next) => _pushSnapshot());

    return MaterialApp(
      title: 'Nudge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const TodoListScreen(),
    );
  }
}
