// Drives RemoteTodoRepository against a running server, so the client code and
// the API contract are checked against each other rather than against mocks.
//
//   dart run tool/smoke_remote.dart http://127.0.0.1:8080 <token>
//   dart run tool/smoke_remote.dart https://localhost <token> --insecure
//
// --insecure skips certificate verification, for a staging host using its own
// CA. Never use it against a real deployment.
//
// Exits non-zero on the first mismatch.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:nudge/core/errors/app_failure.dart';
import 'package:nudge/features/todos/data/remote_todo_repository.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();

  if (positional.length < 2) {
    stderr.writeln(
      'usage: dart run tool/smoke_remote.dart <baseUrl> <token> [--insecure]',
    );
    exit(2);
  }

  final origin = positional[0].replaceAll(RegExp(r'/+$'), '');
  final token = positional[1];
  final repo = RemoteTodoRepository(
    dio: _dio(verifyCertificates: !flags.contains('--insecure')),
    apiBase: '$origin/api/v1',
    token: token,
  );

  var failures = 0;
  void check(String label, bool ok, [String? detail]) {
    stdout.writeln(
      '${ok ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : '  ($detail)'}',
    );
    if (!ok) failures++;
  }

  // Start clean so repeat runs are deterministic.
  for (final stale in await repo.getTodos()) {
    await repo.deleteTodo(stale.id);
  }

  const id = '5c1f2a70-9d3e-4f6b-8a21-0d4e7c9b1a30';
  final created = await repo.createTodo('  Smoke test  ', id: id);
  check('create trims text', created.text == 'Smoke test', created.text);
  check('create honours the client id', created.id == id, created.id);
  check('create starts active', !created.isArchived);
  check('create sets archivedAt to null', created.archivedAt == null);

  final repeated = await repo.createTodo('Different', id: id);
  check(
    'repeating an id is idempotent',
    repeated.text == 'Smoke test',
    repeated.text,
  );

  final listed = await repo.getTodos();
  check('list returns the todo', listed.length == 1, '${listed.length} rows');

  final archived = await repo.updateTodo(id, isArchived: true);
  check('archive sets isArchived', archived.isArchived);
  check('archive sets archivedAt', archived.archivedAt != null);

  final active = await repo.getTodos(filter: TodoFilter.active);
  check(
    'active filter excludes archived',
    active.isEmpty,
    '${active.length} rows',
  );
  final archivedOnly = await repo.getTodos(filter: TodoFilter.archived);
  check('archived filter includes it', archivedOnly.length == 1);

  final restored = await repo.updateTodo(id, isArchived: false);
  check('restore clears archivedAt', restored.archivedAt == null);

  final edited = await repo.updateTodo(id, text: 'Edited text');
  check('edit changes text', edited.text == 'Edited text', edited.text);
  check('edit keeps createdAt', edited.createdAt == created.createdAt);

  await repo.deleteTodo(id);
  check('delete removes it', (await repo.getTodos()).isEmpty);
  await repo.deleteTodo(id); // must not throw
  check('delete is idempotent', true);

  // Error mapping against the real server.
  final badToken = RemoteTodoRepository(
    dio: _dio(verifyCertificates: false),
    apiBase: '$origin/api/v1',
    token: 'definitely-wrong',
  );
  try {
    await badToken.getTodos();
    check('a wrong token is rejected', false, 'no error thrown');
  } on UnauthorizedFailure {
    check('a wrong token maps to UnauthorizedFailure', true);
  } catch (e) {
    check('a wrong token maps to UnauthorizedFailure', false, '$e');
  }

  final unreachable = RemoteTodoRepository(
    dio: _dio(verifyCertificates: false),
    apiBase: 'http://127.0.0.1:1/api/v1',
    token: token,
  );
  try {
    await unreachable.getTodos();
    check(
      'an unreachable server raises NetworkFailure',
      false,
      'no error thrown',
    );
  } on NetworkFailure {
    check('an unreachable server raises NetworkFailure', true);
  } catch (e) {
    check('an unreachable server raises NetworkFailure', false, '$e');
  }

  stdout.writeln(
    failures == 0 ? '\nall checks passed' : '\n$failures check(s) failed',
  );
  exit(failures == 0 ? 0 : 1);
}

Dio _dio({required bool verifyCertificates}) {
  final dio = Dio();
  if (!verifyCertificates) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()..badCertificateCallback = (_, _, _) => true,
    );
  }
  return dio;
}
