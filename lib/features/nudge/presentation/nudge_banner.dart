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
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              Icons.notifications_active,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pending ${pending == 1 ? 'thing' : 'things'} to do',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(nudgeBannerProvider.notifier).hide();
                ref.read(nudgePlatformProvider).dismiss();
              },
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}
