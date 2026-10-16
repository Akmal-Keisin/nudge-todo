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

  Future<Map<String, Todo>> _loadAll() async {
    final json = await _prefs.getString(_key);
    if (json == null) return {};
    final list = jsonDecode(json) as List<dynamic>;
    return {
      for (final item in list)
        (item as Map<String, dynamic>)['id'] as String: Todo.fromJson(item),
    };
  }

  Future<void> _saveAll(Map<String, Todo> todos) async {
    final json = jsonEncode(todos.values.map((t) => t.toJson()).toList());
    await _prefs.setString(_key, json);
  }

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    final todos = await _loadAll();
    return applyFilterAndSort(todos.values, filter);
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    final todos = await _loadAll();
    final todo = Todo(id: id, text: text.trim());
    todos[todo.id] = todo;
    await _saveAll(todos);
    return todo;
  }

  /// Replaces the whole cache. Used when a remote read gives the full list.
  Future<void> replaceAll(List<Todo> todos) async {
    await _saveAll({for (final todo in todos) todo.id: todo});
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    final todos = await _loadAll();
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
    await _saveAll(todos);
    return updated;
  }

  @override
  Future<void> deleteTodo(String id) async {
    final todos = await _loadAll();
    todos.remove(id);
    await _saveAll(todos);
  }

  Future<void> pruneExpired() async {
    final todos = await _loadAll();
    todos.removeWhere((_, todo) => todo.isExpired);
    await _saveAll(todos);
  }
}
