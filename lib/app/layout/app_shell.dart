import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/nudge/presentation/settings_screen.dart';
import '../../features/todos/application/todo_providers.dart';
import '../../features/todos/domain/todo_repository.dart';
import '../../features/todos/presentation/todo_list_screen.dart';
import 'app_breakpoints.dart';
import 'system_ui.dart';

/// Chooses between the phone layout and a rail-based desktop/tablet layout.
/// Width is the only input; platform checks stay out of the UI.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  TodoFilter _todoFilter = TodoFilter.active;

  void _select(int index) {
    if (index < 2) {
      final filter = index == 1 ? TodoFilter.archived : TodoFilter.active;
      if (_selectedIndex == index && _todoFilter == filter) return;
      setState(() {
        _selectedIndex = index;
        _todoFilter = filter;
      });
      return;
    }
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final layout = AppBreakpoints.layoutFor(width);

    if (layout != AppLayout.expanded) {
      return const TodoListScreen();
    }

    final activeCount =
        ref
            .watch(todoListProvider)
            .value
            ?.where((todo) => !todo.isArchived)
            .length ??
        0;
    final extended = width >= AppBreakpoints.extendedRail;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _select(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _select(1),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _select(2),
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: nudgeOverlayStyle(context),
        child: Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  minExtendedWidth: 220,
                  labelType: extended ? null : NavigationRailLabelType.all,
                  leading: _RailBrand(extended: extended),
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _select,
                  destinations: [
                    NavigationRailDestination(
                      icon: _ActiveBadge(
                        count: activeCount,
                        child: const Icon(Icons.task_alt_outlined),
                      ),
                      selectedIcon: _ActiveBadge(
                        count: activeCount,
                        child: const Icon(Icons.task_alt),
                      ),
                      label: const Text('Active', key: ValueKey('rail-active')),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Archive', key: ValueKey('rail-archive')),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings', key: ValueKey('rail-settings')),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex == 2 ? 1 : 0,
                    children: [
                      TodoListScreen(
                        embedded: true,
                        filter: _todoFilter,
                        onFilterChanged: (filter) {
                          setState(() {
                            _todoFilter = filter;
                            _selectedIndex = filter == TodoFilter.archived
                                ? 1
                                : 0;
                          });
                        },
                      ),
                      const SettingsScreen(embedded: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(extended ? 16 : 12, 16, 16, 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/app_icon.png',
              width: 32,
              height: 32,
              filterQuality: FilterQuality.medium,
            ),
          ),
          if (extended) ...[
            const SizedBox(width: 12),
            Text('Nudge', style: theme.textTheme.titleLarge),
          ],
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge.count(count: count, isLabelVisible: count > 0, child: child);
  }
}
