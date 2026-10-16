import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/errors/app_failure.dart';
import 'package:nudge/features/todos/data/caching_todo_repository.dart';
import 'package:nudge/features/todos/data/local_todo_repository.dart';
import 'package:nudge/features/todos/domain/todo.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A remote repository whose behaviour each test dictates.
class _FakeRemote implements TodoRepository {
  _FakeRemote();

  List<Todo> stored = [];
  AppFailure? failWith;
  int getCalls = 0;
  int createCalls = 0;
  String? lastCreatedId;

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    getCalls++;
    _maybeFail();
    return List.of(stored);
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    createCalls++;
    lastCreatedId = id;
    _maybeFail();
    final todo = Todo(id: id, text: text.trim());
    stored.add(todo);
    return todo;
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    _maybeFail();
    final index = stored.indexWhere((t) => t.id == id);
    if (index < 0) throw const NotFoundFailure();
    var todo = stored[index];
    if (text != null) todo = todo.copyWith(text: text.trim());
    if (isArchived != null) {
      todo = isArchived ? todo.archive() : todo.restore();
    }
    stored[index] = todo;
    return todo;
  }

  @override
  Future<void> deleteTodo(String id) async {
    _maybeFail();
    stored.removeWhere((t) => t.id == id);
  }
}

void main() {
  late LocalTodoRepository cache;
  late _FakeRemote remote;
  late List<bool> connectivityReports;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    cache = LocalTodoRepository(SharedPreferencesAsync());
    remote = _FakeRemote();
    connectivityReports = [];
  });

  CachingTodoRepository build() => CachingTodoRepository(
    remote: remote,
    cache: cache,
    onConnectivityChanged: ({required offline}) =>
        connectivityReports.add(offline),
  );

  test('a successful read refreshes the cache and reports online', () async {
    remote.stored = [Todo(id: 'a', text: 'From server')];

    final result = await build().getTodos();

    expect(result.single.text, 'From server');
    expect(connectivityReports, [false]);
    // The cache now holds the server's copy.
    expect((await cache.getTodos()).single.text, 'From server');
  });

  test(
    'an unreachable server falls back to the cache and reports offline',
    () async {
      final repo = build();
      remote.stored = [Todo(id: 'a', text: 'Cached earlier')];
      await repo.getTodos(); // prime the cache

      remote.failWith = const NetworkFailure();
      final result = await repo.getTodos();

      expect(result.single.text, 'Cached earlier');
      expect(connectivityReports.last, isTrue);
    },
  );

  test(
    'a server error other than a network failure is not swallowed',
    () async {
      final repo = build();
      remote.failWith = const UnauthorizedFailure();

      await expectLater(repo.getTodos(), throwsA(isA<UnauthorizedFailure>()));
    },
  );

  test('writes go to the server and mirror into the cache', () async {
    final repo = build();
    await repo.createTodo('Buy milk', id: 'fixed');

    expect(remote.createCalls, 1);
    expect(remote.lastCreatedId, 'fixed');
    expect((await cache.getTodos()).single.text, 'Buy milk');
  });

  test('archiving mirrors into the cache', () async {
    final repo = build();
    final created = await repo.createTodo('Archive me');
    await repo.updateTodo(created.id, isArchived: true);

    final cached = await cache.getTodos(filter: TodoFilter.archived);
    expect(cached.single.isArchived, isTrue);
    expect(cached.single.archivedAt, isNotNull);
  });

  test('deleting mirrors into the cache', () async {
    final repo = build();
    final created = await repo.createTodo('Delete me');
    await repo.deleteTodo(created.id);

    expect(await cache.getTodos(), isEmpty);
  });

  test('a failed write propagates and leaves the cache alone', () async {
    final repo = build();
    remote.failWith = const NetworkFailure();

    await expectLater(repo.createTodo('Nope'), throwsA(isA<NetworkFailure>()));
    expect(await cache.getTodos(), isEmpty);
  });

  test('the filter is applied to the fetched list', () async {
    remote.stored = [
      Todo(id: 'a', text: 'Active'),
      Todo(
        id: 'b',
        text: 'Archived',
        isArchived: true,
        archivedAt: DateTime.now().toUtc(),
      ),
    ];

    final active = await build().getTodos(filter: TodoFilter.active);
    expect(active.map((t) => t.id), ['a']);
  });
}
