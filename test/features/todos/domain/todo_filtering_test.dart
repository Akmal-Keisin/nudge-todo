import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/todos/domain/todo.dart';
import 'package:nudge/features/todos/domain/todo_filtering.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';

void main() {
  final now = DateTime.now().toUtc();

  Todo active(String id, {int ageMinutes = 0}) => Todo(
    id: id,
    text: id,
    createdAt: now.subtract(Duration(minutes: ageMinutes)),
  );

  Todo archived(String id, {int archivedDaysAgo = 0}) => Todo(
    id: id,
    text: id,
    isArchived: true,
    archivedAt: now.subtract(Duration(days: archivedDaysAgo)),
    createdAt: now.subtract(Duration(days: archivedDaysAgo + 1)),
  );

  test('active filter returns active todos newest first', () {
    final todos = [active('old', ageMinutes: 10), active('new')];
    final result = applyFilterAndSort(todos, TodoFilter.active);
    expect(result.map((t) => t.id), ['new', 'old']);
  });

  test('archived filter returns archived todos newest first', () {
    final todos = [archived('older', archivedDaysAgo: 5), archived('newer')];
    final result = applyFilterAndSort(todos, TodoFilter.archived);
    expect(result.map((t) => t.id), ['newer', 'older']);
  });

  test('all filter includes both', () {
    final todos = [active('a'), archived('b')];
    expect(applyFilterAndSort(todos, TodoFilter.all), hasLength(2));
  });

  test('expired archived todos are always dropped', () {
    final todos = [active('keep'), archived('expired', archivedDaysAgo: 15)];
    for (final filter in TodoFilter.values) {
      final result = applyFilterAndSort(todos, filter);
      expect(
        result.map((t) => t.id),
        isNot(contains('expired')),
        reason: 'expired todo leaked through filter $filter',
      );
    }
  });

  test('a todo archived exactly at the retention edge is dropped', () {
    final todos = [archived('edge', archivedDaysAgo: 14)];
    expect(applyFilterAndSort(todos, TodoFilter.all), isEmpty);
  });
}
