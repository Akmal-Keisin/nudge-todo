import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/todos/domain/todo.dart';

void main() {
  test('generates an id and timestamps when omitted', () {
    final todo = Todo(text: 'Call the bank');
    expect(todo.id, isNotEmpty);
    expect(todo.isArchived, isFalse);
    expect(todo.archivedAt, isNull);
    expect(todo.createdAt.isUtc, isTrue);
  });

  test('archive sets archivedAt and restore clears it', () {
    final todo = Todo(text: 'Water the plants');
    final archived = todo.archive();
    expect(archived.isArchived, isTrue);
    expect(archived.archivedAt, isNotNull);

    final restored = archived.restore();
    expect(restored.isArchived, isFalse);
    expect(restored.archivedAt, isNull);
  });

  test('marks archived todos older than 14 days as expired', () {
    final old = Todo(
      text: 'Old thing',
      isArchived: true,
      archivedAt: DateTime.now().toUtc().subtract(const Duration(days: 14)),
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 30)),
    );
    expect(old.isExpired, isTrue);

    final recent = Todo(
      text: 'Recent thing',
      isArchived: true,
      archivedAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
    );
    expect(recent.isExpired, isFalse);
  });

  test('active todos never expire', () {
    final todo = Todo(
      text: 'Active',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 100)),
    );
    expect(todo.isExpired, isFalse);
  });

  test('equality is by id', () {
    final a = Todo(id: 'abc', text: 'One');
    final b = Todo(id: 'abc', text: 'Two');
    expect(a, equals(b));
  });

  test('round-trips through JSON', () {
    final todo = Todo(id: 'fixed-id', text: 'Ship it');
    final restored = Todo.fromJson(todo.toJson());
    expect(restored.id, 'fixed-id');
    expect(restored.text, 'Ship it');
    expect(restored.createdAt, todo.createdAt);
  });
}
