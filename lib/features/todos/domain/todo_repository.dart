import 'todo.dart';

abstract class TodoRepository {
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all});

  /// Creates a todo. Pass [id] to re-create a specific todo, which is how undo
  /// restores a deleted item under its original id.
  Future<Todo> createTodo(String text, {String? id});

  Future<Todo> updateTodo(String id, {String? text, bool? isArchived});
  Future<void> deleteTodo(String id);
}

enum TodoFilter { active, archived, all }
