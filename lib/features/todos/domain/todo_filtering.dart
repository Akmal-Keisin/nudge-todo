import 'todo.dart';
import 'todo_repository.dart';

/// Applies a [TodoFilter] to a set of todos, newest first.
///
/// Expired archived todos are always dropped, so a lagging server prune job
/// never surfaces them. Shared by the local and the caching repositories.
List<Todo> applyFilterAndSort(Iterable<Todo> todos, TodoFilter filter) {
  final visible = todos.where((todo) => !todo.isExpired).toList();

  final filtered = switch (filter) {
    TodoFilter.active => visible.where((t) => !t.isArchived).toList(),
    TodoFilter.archived => visible.where((t) => t.isArchived).toList(),
    TodoFilter.all => visible,
  };

  filtered.sort((a, b) {
    if (filter == TodoFilter.archived) {
      return (b.archivedAt ?? b.updatedAt).compareTo(
        a.archivedAt ?? a.updatedAt,
      );
    }
    return b.createdAt.compareTo(a.createdAt);
  });

  return filtered;
}
