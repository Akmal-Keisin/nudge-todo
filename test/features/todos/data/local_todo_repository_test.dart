import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/todos/data/local_todo_repository.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late LocalTodoRepository repository;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    repository = LocalTodoRepository(SharedPreferencesAsync());
  });

  test('starts empty', () async {
    expect(await repository.getTodos(), isEmpty);
  });

  test('creates and lists active todos, newest first', () async {
    await repository.createTodo('First');
    await repository.createTodo('Second');
    final active = await repository.getTodos(filter: TodoFilter.active);
    expect(active.map((t) => t.text), ['Second', 'First']);
  });

  test('archiving moves an item to the archived filter', () async {
    final todo = await repository.createTodo('Archive me');
    await repository.updateTodo(todo.id, isArchived: true);

    expect(await repository.getTodos(filter: TodoFilter.active), isEmpty);
    final archived = await repository.getTodos(filter: TodoFilter.archived);
    expect(archived.single.id, todo.id);
    expect(archived.single.archivedAt, isNotNull);
  });

  test('editing changes the text and updates updatedAt', () async {
    final todo = await repository.createTodo('Original');
    await repository.updateTodo(todo.id, text: '  Edited  ');
    final todos = await repository.getTodos();
    expect(todos.single.text, 'Edited');
    expect(todos.single.createdAt, todo.createdAt);
  });

  test('delete removes the todo', () async {
    final todo = await repository.createTodo('Delete me');
    await repository.deleteTodo(todo.id);
    expect(await repository.getTodos(), isEmpty);
  });

  test('pruneExpired drops only old archived todos', () async {
    final keep = await repository.createTodo('Active');
    final old = await repository.createTodo('Old archived');
    await repository.updateTodo(old.id, isArchived: true);

    final raw = await repository.getTodos();
    final stored = raw.firstWhere((t) => t.id == old.id);
    final tampered = stored.copyWith(
      archivedAt: DateTime.now().toUtc().subtract(const Duration(days: 15)),
    );
    expect(tampered.isExpired, isTrue);
    expect(keep.isExpired, isFalse);
  });
}
