import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/errors/app_failure.dart';
import 'package:nudge/features/todos/application/todo_providers.dart';
import 'package:nudge/features/todos/domain/todo.dart';
import 'package:nudge/features/todos/domain/todo_filtering.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';

void main() {
  ProviderContainer containerFor(_FakeRepository repository) {
    final container = ProviderContainer(
      overrides: [todoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('loads the list a single time', () async {
    final repository = _FakeRepository([Todo(id: 'a', text: 'One')]);
    final container = containerFor(repository);

    await container.read(todoListProvider.future);

    expect(repository.getTodosCalls, 1);
  });

  test('a write updates the list without ever entering loading', () async {
    final repository = _FakeRepository([Todo(id: 'a', text: 'One')]);
    final container = containerFor(repository);
    await container.read(todoListProvider.future);

    final states = <AsyncValue<List<Todo>>>[];
    container.listen(todoListProvider, (previous, next) => states.add(next));

    await container.read(todoListProvider.notifier).add('Two');

    expect(states, isNotEmpty);
    expect(states.any((state) => state.isLoading), isFalse);
    expect(
      container.read(todoListProvider).value!.map((todo) => todo.text),
      containsAll(['One', 'Two']),
    );
  });

  test('a failed write rolls the list back and reports the failure', () async {
    final repository = _FakeRepository([Todo(id: 'a', text: 'One')]);
    final container = containerFor(repository);
    await container.read(todoListProvider.future);

    repository.failWith = const NetworkFailure();
    await container.read(todoListProvider.notifier).add('Two');

    expect(container.read(todoListProvider).value, hasLength(1));
    expect(container.read(todoErrorProvider), isA<NetworkFailure>());
  });

  test('archiving is optimistic and rolls back on failure', () async {
    final repository = _FakeRepository([Todo(id: 'a', text: 'One')]);
    final container = containerFor(repository);
    await container.read(todoListProvider.future);

    await container.read(todoListProvider.notifier).toggleArchive('a');
    expect(container.read(todoListProvider).value!.single.isArchived, isTrue);

    repository.failWith = const ServerFailure();
    await container.read(todoListProvider.notifier).toggleArchive('a');
    expect(container.read(todoListProvider).value!.single.isArchived, isTrue);
    expect(container.read(todoErrorProvider), isA<ServerFailure>());
  });

  test('refresh keeps the current list without entering loading', () async {
    final repository = _FakeRepository([Todo(id: 'a', text: 'One')]);
    final container = containerFor(repository);
    await container.read(todoListProvider.future);

    final states = <AsyncValue<List<Todo>>>[];
    container.listen(todoListProvider, (previous, next) => states.add(next));

    await container.read(todoListProvider.notifier).refresh();

    expect(states.any((state) => state.isLoading), isFalse);
    expect(container.read(todoListProvider).value, hasLength(1));
    expect(container.read(refreshingProvider), isFalse);
  });
}

class _FakeRepository implements TodoRepository {
  _FakeRepository(this._todos);

  final List<Todo> _todos;

  /// When set, every write throws it, so rollback can be exercised.
  AppFailure? failWith;
  int getTodosCalls = 0;

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    getTodosCalls++;
    return applyFilterAndSort(_todos, filter);
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    _maybeFail();
    final todo = Todo(id: id, text: text.trim());
    _todos.add(todo);
    return todo;
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    _maybeFail();
    final index = _todos.indexWhere((todo) => todo.id == id);
    var updated = _todos[index];
    if (text != null) updated = updated.copyWith(text: text.trim());
    if (isArchived != null) {
      updated = isArchived ? updated.archive() : updated.restore();
    }
    _todos[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodo(String id) async {
    _maybeFail();
    _todos.removeWhere((todo) => todo.id == id);
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) throw failure;
  }
}
