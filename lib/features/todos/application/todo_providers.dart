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

/// The one place the local and remote implementations are chosen between, so
/// switching to the backend is a single swap and tests can override it.
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  final cache = LocalTodoRepository(ref.watch(sharedPreferencesProvider));
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

class _TodoFilterNotifier extends Notifier<TodoFilter> {
  @override
  TodoFilter build() => TodoFilter.all;

  void set(TodoFilter filter) => state = filter;
}

final todoFilterProvider = NotifierProvider<_TodoFilterNotifier, TodoFilter>(
  _TodoFilterNotifier.new,
);

final todoListProvider = AsyncNotifierProvider<TodoListController, List<Todo>>(
  TodoListController.new,
);

class TodoListController extends AsyncNotifier<List<Todo>> {
  TodoRepository get _repo => ref.read(todoRepositoryProvider);

  @override
  Future<List<Todo>> build() async {
    final filter = ref.watch(todoFilterProvider);
    final repo = ref.watch(todoRepositoryProvider);
    return repo.getTodos(filter: filter);
  }

  /// [id] re-creates a specific todo, which is how undo restores a deleted one.
  Future<void> add(String text, {String? id}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > Todo.maxLength) return;
    await _mutate(() async {
      await _repo.createTodo(trimmed, id: id);
    });
  }

  Future<void> edit(String id, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed.length > Todo.maxLength) return;
    await _mutate(() async {
      await _repo.updateTodo(id, text: trimmed);
    });
  }

  Future<void> toggleArchive(String id) async {
    await _mutate(() async {
      final current = await _repo.getTodos();
      final todo = current.firstWhere((t) => t.id == id);
      await _repo.updateTodo(id, isArchived: !todo.isArchived);
    });
  }

  Future<void> restore(String id) async {
    await _mutate(() async {
      await _repo.updateTodo(id, isArchived: false);
    });
  }

  Future<void> remove(String id) async {
    await _mutate(() async {
      await _repo.deleteTodo(id);
    });
  }

  Future<void> refresh() async {
    await _pruneCacheIfLocal();
    await _mutate(() async {});
  }

  /// Runs a write and reloads the list, normalising every error to an
  /// [AppFailure] so the UI never shows a raw exception.
  Future<void> _mutate(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = AsyncData(
        await _repo.getTodos(filter: ref.read(todoFilterProvider)),
      );
    } on AppFailure catch (failure, stack) {
      state = AsyncError(failure, stack);
    } catch (error, stack) {
      state = AsyncError(const ServerFailure(), stack);
    }
  }

  Future<void> _pruneCacheIfLocal() async {
    final repo = _repo;
    if (repo is LocalTodoRepository) {
      await repo.pruneExpired();
    }
  }
}
