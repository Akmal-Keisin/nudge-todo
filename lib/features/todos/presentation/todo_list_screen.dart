import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/layout/app_breakpoints.dart';
import '../../../app/layout/pane_header.dart';
import '../../../app/layout/system_ui.dart';
import '../../../core/errors/app_failure.dart';
import '../../nudge/presentation/nudge_banner.dart';
import '../../nudge/presentation/settings_screen.dart';
import '../../settings/application/settings_providers.dart';
import '../application/todo_providers.dart';
import '../domain/todo.dart';
import '../domain/todo_filtering.dart';
import '../domain/todo_repository.dart';
import 'offline_banner.dart';
import 'todo_row.dart';
import 'todo_skeleton.dart';

class TodoListScreen extends ConsumerStatefulWidget {
  const TodoListScreen({
    this.embedded = false,
    this.filter,
    this.onFilterChanged,
    super.key,
  });

  /// True when the screen lives inside the expanded [AppShell] pane. In that
  /// mode it renders no Scaffold or AppBar and the rail owns navigation.
  final bool embedded;

  /// The filter selected by the shell. Null means the screen owns its tabs.
  final TodoFilter? filter;

  /// Called from the shell layout when a shortcut changes the filter.
  final ValueChanged<TodoFilter>? onFilterChanged;

  @override
  ConsumerState<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends ConsumerState<TodoListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// A device that changed elsewhere is picked up here. Nothing on this device
  /// needs a poll, and resume/manual refresh cover the responsive cases, so the
  /// interval is long and only runs when a server is configured.
  static const _refreshInterval = Duration(minutes: 5);

  late final TabController _tabController;
  final _composerController = TextEditingController();
  final _composerFocus = FocusNode();
  final _activeScroll = ScrollController();
  final _archiveScroll = ScrollController();
  String? _expandedId;
  Timer? _refreshTimer;
  bool _syncingTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _indexFor(widget.filter),
      // Swap the list in place instead of sliding the page over ~300ms. The
      // slide showed the outgoing list for the whole transition, which read as
      // a delay before the new list appeared. Swiping still animates: that is
      // driven by the PageView's drag physics, not this duration.
      animationDuration: Duration.zero,
    );
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(TodoListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filter = widget.filter;
    if (filter == null || filter == oldWidget.filter) return;

    final index = _indexFor(filter);
    if (_tabController.index != index) {
      _syncingTab = true;
      _tabController.index = index;
      _syncingTab = false;
    }
    _expandedId = null;
  }

  int _indexFor(TodoFilter? filter) {
    return filter == TodoFilter.archived ? 1 : 0;
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      // Local-only installs have nothing to poll for.
      final configured =
          ref.read(apiSettingsProvider).value?.configured ?? false;
      if (!configured) return;
      ref.read(todoListProvider.notifier).refresh();
    });
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
    if (_syncingTab) return;
    setState(() => _expandedId = null);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    _activeScroll.dispose();
    _archiveScroll.dispose();
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

  void _openSettings() {
    if (widget.embedded) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _selectFilter(TodoFilter filter) {
    if (widget.embedded) {
      widget.onFilterChanged?.call(filter);
      return;
    }
    final index = _indexFor(filter);
    if (_tabController.index != index) {
      _tabController.index = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(todoListProvider);
    final refreshing = ref.watch(refreshingProvider);
    final width = MediaQuery.sizeOf(context).width;
    final layout = AppBreakpoints.layoutFor(width);
    final activeCount =
        all.value?.where((todo) => !todo.isArchived).length ?? 0;

    ref.listen(todoErrorProvider, (previous, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(next.message)));
      ref.read(todoErrorProvider.notifier).clear();
    });

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
          _composerFocus.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
          ref.read(todoListProvider.notifier).refresh(),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          setState(() => _expandedId = null),
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          _selectFilter(TodoFilter.active),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          _selectFilter(TodoFilter.archived),
      if (!widget.embedded)
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
    };

    if (widget.embedded) {
      return CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          autofocus: true,
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('todo-content'),
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.contentMaxWidth,
              ),
              child: Column(
                children: [
                  _buildPaneHeader(
                    embedded: true,
                    activeCount: activeCount,
                    all: all,
                  ),
                  Expanded(child: _buildBody(all, refreshing, wide: true)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (layout == AppLayout.medium) {
      return CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          autofocus: true,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: nudgeOverlayStyle(context),
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppBreakpoints.contentMaxWidth,
                        ),
                        child: _buildPaneHeader(
                          embedded: false,
                          activeCount: activeCount,
                          all: all,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          key: const ValueKey('todo-content'),
                          constraints: const BoxConstraints(
                            maxWidth: AppBreakpoints.contentMaxWidth,
                          ),
                          child: _buildBody(all, refreshing, wide: true),
                        ),
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

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(activeCount),
          body: Center(
            child: ConstrainedBox(
              key: const ValueKey('todo-content'),
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.contentMaxWidth,
              ),
              child: _buildBody(all, refreshing, wide: false),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(int activeCount) {
    return AppBar(
      title: Text(
        _tabController.index == 0 ? 'Nudge ($activeCount)' : 'Archive',
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
          onPressed: _openSettings,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Active'),
          Tab(text: 'Archive'),
        ],
      ),
    );
  }

  Widget _buildPaneHeader({
    required bool embedded,
    required int activeCount,
    required AsyncValue<List<Todo>> all,
  }) {
    final isArchive = _tabController.index == 1;
    final archivedCount = applyFilterAndSort(
      all.value ?? const <Todo>[],
      TodoFilter.archived,
    ).length;
    final title = embedded ? (isArchive ? 'Archive' : 'Active') : 'Nudge';
    final subtitle = isArchive
        ? '$archivedCount archived'
        : '$activeCount ${activeCount == 1 ? 'thing' : 'things'} to do';

    return PaneHeader(
      key: const ValueKey('todo-pane-header'),
      title: title,
      subtitle: subtitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () => ref.read(todoListProvider.notifier).refresh(),
        ),
        if (!embedded)
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
      ],
      tabs: embedded ? null : _buildFilterTabs(),
    );
  }

  Widget _buildFilterTabs() {
    final selected = _tabController.index == 1
        ? TodoFilter.archived
        : TodoFilter.active;

    return SegmentedButton<TodoFilter>(
      key: const ValueKey('todo-filter-tabs'),
      segments: const [
        ButtonSegment(value: TodoFilter.active, label: Text('Active')),
        ButtonSegment(value: TodoFilter.archived, label: Text('Archive')),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => _selectFilter(selection.first),
    );
  }

  Widget _buildBody(
    AsyncValue<List<Todo>> all,
    bool refreshing, {
    required bool wide,
  }) {
    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(minHeight: 2),
        const NudgeBanner(),
        const OfflineBanner(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: widget.embedded
                ? const NeverScrollableScrollPhysics()
                : null,
            children: [
              _buildActiveTab(all, wide: wide),
              _buildArchiveTab(all, wide: wide),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTab(AsyncValue<List<Todo>> todos, {required bool wide}) {
    final offline = ref.watch(offlineProvider);

    return Column(
      children: [
        Expanded(
          child: todos.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            data: (all) {
              final list = applyFilterAndSort(all, TodoFilter.active);
              if (list.isEmpty) {
                return _emptyList(
                  'No active todos',
                  icon: Icons.task_alt,
                  hint: 'Add one below and Nudge will remind you.',
                  controller: _activeScroll,
                  wide: wide,
                );
              }
              return Scrollbar(
                controller: _activeScroll,
                thumbVisibility: wide,
                child: RefreshIndicator(
                  onRefresh: () =>
                      ref.read(todoListProvider.notifier).refresh(),
                  child: ListView.builder(
                    controller: _activeScroll,
                    padding: EdgeInsets.only(top: 8, bottom: wide ? 16 : 80),
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
                            _expandedId = _expandedId == todo.id
                                ? null
                                : todo.id;
                          });
                        },
                        onToggleArchive: () {
                          ref
                              .read(todoListProvider.notifier)
                              .toggleArchive(todo.id);
                          _showUndo(
                            'Archived',
                            () => ref
                                .read(todoListProvider.notifier)
                                .restore(todo.id),
                          );
                        },
                        onEdit: (newText) {
                          ref
                              .read(todoListProvider.notifier)
                              .edit(todo.id, newText);
                        },
                        onDelete: () {
                          ref.read(todoListProvider.notifier).remove(todo.id);
                          // Re-create under the original id so a later sync
                          // cannot resurrect it as a duplicate.
                          _showUndo(
                            'Deleted',
                            () => ref
                                .read(todoListProvider.notifier)
                                .add(todo.text, id: todo.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
            loading: () => const TodoSkeleton(),
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
        _buildComposer(enabled: !offline, wide: wide),
      ],
    );
  }

  Widget _buildComposer({required bool enabled, required bool wide}) {
    final theme = Theme.of(context);
    final field = Row(
      children: [
        Expanded(
          child: TextField(
            controller: _composerController,
            focusNode: _composerFocus,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: enabled ? 'Add a todo...' : 'Offline',
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
    );

    if (!wide) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: field,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: field,
      ),
    );
  }

  /// An empty state that still scrolls, so pull-to-refresh works with no rows.
  Widget _emptyList(
    String message, {
    required IconData icon,
    required String hint,
    required ScrollController controller,
    required bool wide,
  }) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;

        return Scrollbar(
          controller: controller,
          thumbVisibility: wide,
          child: RefreshIndicator(
            onRefresh: () => ref.read(todoListProvider.notifier).refresh(),
            child: ListView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 34,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          message,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArchiveTab(AsyncValue<List<Todo>> todos, {required bool wide}) {
    final offline = ref.watch(offlineProvider);

    return todos.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (all) {
        final list = applyFilterAndSort(all, TodoFilter.archived);
        if (list.isEmpty) {
          return _emptyList(
            'Nothing archived yet',
            icon: Icons.inventory_2_outlined,
            hint: 'Checked todos land here for 14 days.',
            controller: _archiveScroll,
            wide: wide,
          );
        }
        return Scrollbar(
          controller: _archiveScroll,
          thumbVisibility: wide,
          child: RefreshIndicator(
            onRefresh: () => ref.read(todoListProvider.notifier).refresh(),
            child: ListView.builder(
              controller: _archiveScroll,
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
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
          ),
        );
      },
      loading: () => const TodoSkeleton(),
      error: (error, _) => Center(child: Text(failureMessage(error))),
    );
  }
}

/// Human-readable text for anything a provider might surface as an error.
String failureMessage(Object error) {
  return error is AppFailure ? error.message : 'Something went wrong.';
}
