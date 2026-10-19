import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/todo.dart';
import '../domain/todo_filtering.dart';
import '../domain/todo_repository.dart';

class LocalTodoRepository implements TodoRepository {
  LocalTodoRepository(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _key = 'nudge_todos';

  /// Decoded once and kept in memory. Every method works on this map, so a
  /// write no longer re-decodes the whole list just to add one item.
  Map<String, Todo>? _cache;

  Future<Map<String, Todo>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final json = await _prefs.getString(_key);
    if (json == null) return _cache = <String, Todo>{};
    final list = jsonDecode(json) as List<dynamic>;
    return _cache = {
      for (final item in list)
        (item as Map<String, dynamic>)['id'] as String: Todo.fromJson(item),
    };
  }

  Future<void> _persist() async {
    final todos = _cache ?? const <String, Todo>{};
    final json = jsonEncode(todos.values.map((t) => t.toJson()).toList());
    await _prefs.setString(_key, json);
  }

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    final todos = await _load();
    return applyFilterAndSort(todos.values, filter);
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    final todos = await _load();
    final todo = Todo(id: id, text: text.trim());
    todos[todo.id] = todo;
    await _persist();
    return todo;
  }

  /// Replaces the whole cache. Used when a remote read gives the full list.
  Future<void> replaceAll(List<Todo> todos) async {
    _cache = {for (final todo in todos) todo.id: todo};
    await _persist();
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    final todos = await _load();
    final existing = todos[id];
    if (existing == null) {
      throw const NotFoundFailure();
    }
    var updated = existing;
    if (text != null) {
      updated = updated.copyWith(text: text.trim());
    }
    if (isArchived != null) {
      updated = isArchived ? updated.archive() : updated.restore();
    }
    todos[id] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<void> deleteTodo(String id) async {
    final todos = await _load();
    todos.remove(id);
    await _persist();
  }

  Future<void> pruneExpired() async {
    final todos = await _load();
    final before = todos.length;
    todos.removeWhere((_, todo) => todo.isExpired);
    if (todos.length != before) await _persist();
  }
}
