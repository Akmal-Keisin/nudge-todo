import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_providers.dart';
import '../../todos/application/todo_providers.dart';
import '../application/nudge_providers.dart';

class NudgeBanner extends ConsumerWidget {
  const NudgeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(nudgeBannerProvider);
    if (!visible) return const SizedBox.shrink();

    final todos = ref.watch(todoListProvider).value ?? const [];
    final pending = todos.where((t) => !t.isArchived).length;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.onPrimaryContainer.withValues(
                alpha: 0.12,
              ),
              child: Icon(
                Icons.notifications_active,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pending ${pending == 1 ? 'thing' : 'things'} to do',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
              ),
              onPressed: () async {
                ref.read(nudgeBannerProvider.notifier).hide();
                await ref.read(nudgePlatformProvider).dismiss();
              },
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}
