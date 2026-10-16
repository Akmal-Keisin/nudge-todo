import '../../../core/platform/nudge_platform.dart';
import '../../todos/domain/todo.dart';
import '../domain/nudge_config.dart';

/// Builds the payload pushed to the platform: what native needs to decide, and
/// what the notification/window shows.
NudgeSnapshot buildNudgeSnapshot({
  required NudgeConfig config,
  required List<Todo> todos,
}) {
  final active = todos.where((todo) => !todo.isArchived).toList();
  return NudgeSnapshot(
    pendingCount: active.length,
    titles: active.take(5).map((todo) => todo.text).toList(),
    enabled: config.enabled,
    cooldownMinutes: config.cooldownMinutes,
    showTextInNotifications: config.showTextInNotifications,
  );
}
