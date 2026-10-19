import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/storage/storage_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../data/caching_todo_repository.dart';
import '../data/local_todo_repository.dart';
import '../data/remote_todo_repository.dart';
import '../domain/todo.dart';
import '../domain/todo_repository.dart';

/// True when the last server call could not be reached, so the UI shows the
/// cached list and refuses writes.
class OfflineController extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool offline}) {
    if (state != offline) state = offline;
  }
}

final offlineProvider = NotifierProvider<OfflineController, bool>(
  OfflineController.new,
);

/// The last write that failed and was rolled back. The list stays on screen;
/// the screen watches this to show a message instead of replacing the list with
/// an error page.
class TodoErrorController extends Notifier<AppFailure?> {
  @override
  AppFailure? build() => null;

  void report(AppFailure failure) => state = failure;

  void clear() => state = null;
}

final todoErrorProvider = NotifierProvider<TodoErrorController, AppFailure?>(
  TodoErrorController.new,
);

/// True while a silent background refresh is in flight, so the screen can show
/// a thin progress bar instead of blanking the list.
class RefreshingController extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool refreshing}) {
    if (state != refreshing) state = refreshing;
  }
}

final refreshingProvider = NotifierProvider<RefreshingController, bool>(
  RefreshingController.new,
);

/// One instance per container. Keeping the local repository stable means the
/// local-only case returns the *same* object before and after the stored
/// settings finish loading, so Riverpod skips the dependent rebuild and the
/// list is not read twice at startup. A configured server deliberately returns
/// a different repository: the cached list shows first, then the server syncs.
final localTodoRepositoryProvider = Provider<LocalTodoRepository>((ref) {
  return LocalTodoRepository(ref.watch(sharedPreferencesProvider));
});

/// The one place the local and remote implementations are chosen between, so
/// switching to the backend is a single swap and tests can override it.
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  final cache = ref.watch(localTodoRepositoryProvider);
  final settings = ref.watch(apiSettingsProvider).value;

  if (settings == null || !settings.configured) {
    return cache;
  }

  return CachingTodoRepository(
    remote: RemoteTodoRepository(
      dio: ref.watch(dioProvider),
      apiBase: settings.apiBase,
      token: settings.token,
    ),
    cache: cache,
    onConnectivityChanged: ({required offline}) {
      ref.read(offlineProvider.notifier).set(offline: offline);
    },
  );
});

final todoListProvider = AsyncNotifierProvider<TodoListController, List<Todo>>(
  TodoListController.new,
);

class TodoListController extends AsyncNotifier<List<Todo>> {
  /// Guards against overlapping background refreshes (timer plus resume plus
  /// pull-to-refresh all funnel into [refresh]).
  bool _refreshing = false;

  TodoRepository get _repo => ref.read(todoRepositoryProvider);

  /// Holds the whole list rather than one tab's slice, so switching tabs is an
  /// in-memory filter and never reloads.
  @override
  Future<List<Todo>> build() {
    return ref.watch(todoRepositoryProvider).getTodos();
  }

  /// [id] re-creates a specific todo, which is how undo restores a deleted one.
  Future<void> add(String text, {String? id}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > Todo.maxLength) return;
    final created = Todo(id: id, text: trimmed);
    await _optimistic(
      (previous) => [created, ...previous.where((t) => t.id != created.id)],
      () => _repo.createTodo(trimmed, id: created.id),
    );
  }

  Future<void> edit(String id, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed.length > Todo.maxLength) return;
    await _optimistic(
      (previous) =>
          _replace(previous, id, (todo) => todo.copyWith(text: trimmed)),
      () => _repo.updateTodo(id, text: trimmed),
    );
  }

  Future<void> toggleArchive(String id) async {
    final todo = _find(id);
    if (todo == null) return;
    final target = !todo.isArchived;
    await _optimistic(
      (previous) => _replace(
        previous,
        id,
        (todo) => target ? todo.archive() : todo.restore(),
      ),
      () => _repo.updateTodo(id, isArchived: target),
    );
  }

  Future<void> restore(String id) async {
    await _optimistic(
      (previous) => _replace(previous, id, (todo) => todo.restore()),
      () => _repo.updateTodo(id, isArchived: false),
    );
  }

  Future<void> remove(String id) async {
    await _optimistic(
      (previous) => previous.where((todo) => todo.id != id).toList(),
      () => _repo.deleteTodo(id),
    );
  }

  /// Refreshes without blanking the list: the timer, resume, pull-to-refresh and
  /// the refresh buttons all use this.
  Future<void> refresh() async {
    if (_refreshing) return;
    final hadValue = state.hasValue;
    _refreshing = true;
    if (hadValue) ref.read(refreshingProvider.notifier).set(refreshing: true);
    try {
      await _pruneCacheIfLocal();
      state = AsyncData(await _repo.getTodos());
    } on AppFailure catch (failure, stack) {
      if (hadValue) {
        _report(failure);
      } else {
        state = AsyncError(failure, stack);
      }
    } catch (error, stack) {
      if (hadValue) {
        _report(const ServerFailure());
      } else {
        state = AsyncError(const ServerFailure(), stack);
      }
    } finally {
      _refreshing = false;
      if (hadValue) {
        ref.read(refreshingProvider.notifier).set(refreshing: false);
      }
    }
  }

  /// Applies [next] to the current list immediately, runs the write, then
  /// reconciles with the repository. A failed write rolls the list back to
  /// [previous] and reports the failure, so the list never disappears for a
  /// spinner and never turns into an error page on a write error.
  Future<void> _optimistic(
    List<Todo> Function(List<Todo> previous) next,
    Future<void> Function() action,
  ) async {
    final previous = state.value ?? const <Todo>[];
    state = AsyncData(next(previous));
    try {
      await action();
      state = AsyncData(await _repo.getTodos());
    } on AppFailure catch (failure) {
      state = AsyncData(previous);
      _report(failure);
    } catch (_) {
      state = AsyncData(previous);
      _report(const ServerFailure());
    }
  }

  Todo? _find(String id) {
    for (final todo in state.value ?? const <Todo>[]) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  List<Todo> _replace(List<Todo> todos, String id, Todo Function(Todo) update) {
    return [
      for (final todo in todos)
        if (todo.id == id) update(todo) else todo,
    ];
  }

  void _report(AppFailure failure) =>
      ref.read(todoErrorProvider.notifier).report(failure);

  Future<void> _pruneCacheIfLocal() async {
    final repo = _repo;
    if (repo is LocalTodoRepository) {
      await repo.pruneExpired();
    }
  }
}
