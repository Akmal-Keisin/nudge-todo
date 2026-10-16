import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../nudge/presentation/nudge_banner.dart';
import '../../nudge/presentation/settings_screen.dart';
import '../application/todo_providers.dart';
import '../domain/todo.dart';
import '../domain/todo_repository.dart';
import 'offline_banner.dart';
import 'todo_row.dart';

class TodoListScreen extends ConsumerStatefulWidget {
  const TodoListScreen({super.key});

  @override
  ConsumerState<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends ConsumerState<TodoListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _refreshInterval = Duration(seconds: 60);

  late final TabController _tabController;
  final _composerController = TextEditingController();
  final _composerFocus = FocusNode();
  String? _expandedId;
  String? _undoId;
  Todo? _undoTodo;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => ref.read(todoListProvider.notifier).refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh on resume and restart the idle timer so a foregrounded app
      // does not immediately fire another refresh.
      ref.read(todoListProvider.notifier).refresh();
      _startRefreshTimer();
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  void _onTabChanged() {
    final filter = _tabController.index == 0
        ? TodoFilter.active
        : TodoFilter.archived;
    ref.read(todoFilterProvider.notifier).set(filter);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _addTodo() {
    final text = _composerController.text.trim();
    if (text.isEmpty || text.length > Todo.maxLength) return;
    ref.read(todoListProvider.notifier).add(text);
    _composerController.clear();
  }

  void _showUndo(String message, VoidCallback onUndo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todoListProvider);

    final activeCount = todos.whenData((list) => list.length);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _composerFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            ref.read(todoListProvider.notifier).refresh(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _expandedId = null),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _tabController.index == 0
                  ? 'Nudge (${activeCount.value ?? 0})'
                  : 'Archive',
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => ref.read(todoListProvider.notifier).refresh(),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Active'),
                Tab(text: 'Archive'),
              ],
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  const NudgeBanner(),
                  const OfflineBanner(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveTab(todos),
                        _buildArchiveTab(todos),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTab(AsyncValue<List<Todo>> todos) {
    final offline = ref.watch(offlineProvider);

    return Column(
      children: [
        Expanded(
          child: todos.when(
            data: (list) {
              if (list.isEmpty) {
                return const Center(
                  child: Text('No active todos. Add one below!'),
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(todoListProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final todo = list[index];
                    return TodoRow(
                      key: ValueKey(todo.id),
                      todo: todo,
                      enabled: !offline,
                      isExpanded: _expandedId == todo.id,
                      onToggleExpand: () {
                        setState(() {
                          _expandedId = _expandedId == todo.id ? null : todo.id;
                        });
                      },
                      onToggleArchive: () {
                        _undoId = todo.id;
                        ref
                            .read(todoListProvider.notifier)
                            .toggleArchive(todo.id);
                        _showUndo('Archived', () {
                          final id = _undoId;
                          if (id == null) return;
                          ref.read(todoListProvider.notifier).restore(id);
                          _undoId = null;
                        });
                      },
                      onEdit: (newText) {
                        ref
                            .read(todoListProvider.notifier)
                            .edit(todo.id, newText);
                      },
                      onDelete: () {
                        _undoTodo = todo;
                        ref.read(todoListProvider.notifier).remove(todo.id);
                        _showUndo('Deleted', () {
                          final deleted = _undoTodo;
                          if (deleted == null) return;
                          // Re-create under the original id so a later sync
                          // cannot resurrect it as a duplicate.
                          ref
                              .read(todoListProvider.notifier)
                              .add(deleted.text, id: deleted.id);
                          _undoTodo = null;
                        });
                      },
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(failureMessage(error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(todoListProvider.notifier).refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildComposer(enabled: !offline),
      ],
    );
  }

  Widget _buildComposer({required bool enabled}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _composerController,
              focusNode: _composerFocus,
              enabled: enabled,
              decoration: InputDecoration(
                hintText: enabled ? 'Add a todo...' : 'Offline',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _addTodo(),
              textInputAction: TextInputAction.done,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enabled ? _addTodo : null,
            icon: const Icon(Icons.add),
            tooltip: 'Add todo',
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveTab(AsyncValue<List<Todo>> todos) {
    final offline = ref.watch(offlineProvider);

    return todos.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('No archived todos.'));
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(todoListProvider.notifier).refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final todo = list[index];
              final daysAgo = DateTime.now()
                  .toUtc()
                  .difference(todo.archivedAt ?? todo.updatedAt)
                  .inDays;
              final daysLeft = 14 - daysAgo;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Checkbox(
                    value: todo.isArchived,
                    onChanged: offline
                        ? null
                        : (_) {
                            ref
                                .read(todoListProvider.notifier)
                                .restore(todo.id);
                          },
                  ),
                  title: Text(
                    todo.text,
                    maxLines: _expandedId == todo.id ? null : 2,
                    overflow: _expandedId == todo.id
                        ? null
                        : TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Done $daysAgo day${daysAgo == 1 ? '' : 's'} ago'
                    ' \u00b7 deleted in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                  ),
                  onTap: () {
                    setState(() {
                      _expandedId = _expandedId == todo.id ? null : todo.id;
                    });
                  },
                  trailing: _expandedId == todo.id && !offline
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'restore') {
                              ref
                                  .read(todoListProvider.notifier)
                                  .restore(todo.id);
                            } else if (action == 'delete') {
                              ref
                                  .read(todoListProvider.notifier)
                                  .remove(todo.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'restore',
                              child: Text('Restore'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(failureMessage(error))),
    );
  }
}

/// Human-readable text for anything a provider might surface as an error.
String failureMessage(Object error) {
  return error is AppFailure ? error.message : 'Something went wrong.';
}
