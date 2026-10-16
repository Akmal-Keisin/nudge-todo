import '../../../core/errors/app_failure.dart';
import '../domain/todo.dart';
import '../domain/todo_filtering.dart';
import '../domain/todo_repository.dart';
import 'local_todo_repository.dart';

/// Makes the backend the source of truth while keeping the list readable
/// offline.
///
/// Reads go to the server and refresh the cache; if the server is unreachable
/// the cached list is returned instead, so the nudge still has something to
/// show. Writes are online-only and let failures through, because silently
/// queueing them would need the sync machinery the plan defers past v1.
class CachingTodoRepository implements TodoRepository {
  CachingTodoRepository({
    required this._remote,
    required this._cache,
    required this._onConnectivityChanged,
  });

  final TodoRepository _remote;
  final LocalTodoRepository _cache;
  final void Function({required bool offline}) _onConnectivityChanged;

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    try {
      // The list is small, so always fetch everything and filter here. That
      // keeps the cache complete for offline reads.
      final all = await _remote.getTodos();
      await _cache.replaceAll(all);
      _onConnectivityChanged(offline: false);
      return applyFilterAndSort(all, filter);
    } on NetworkFailure {
      _onConnectivityChanged(offline: true);
      return _cache.getTodos(filter: filter);
    }
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    final created = await _remote.createTodo(text, id: id);
    await _mirror(() => _cache.createTodo(text, id: created.id));
    _onConnectivityChanged(offline: false);
    return created;
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    final updated = await _remote.updateTodo(
      id,
      text: text,
      isArchived: isArchived,
    );
    await _mirror(
      () => _cache.updateTodo(id, text: text, isArchived: isArchived),
    );
    _onConnectivityChanged(offline: false);
    return updated;
  }

  @override
  Future<void> deleteTodo(String id) async {
    await _remote.deleteTodo(id);
    await _mirror(() => _cache.deleteTodo(id));
    _onConnectivityChanged(offline: false);
  }

  /// The server already has the change, so a cache write that fails must not
  /// turn a successful edit into an error. The next read re-syncs the cache.
  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {}
  }
}
