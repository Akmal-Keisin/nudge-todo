import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/errors/app_failure.dart';
import 'package:nudge/features/todos/data/remote_todo_repository.dart';
import 'package:nudge/features/todos/domain/todo_repository.dart';

/// Serves canned responses without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _todoJson({
  String id = '0b8f4c3e-5d1a-4c52-9a7e-2f6c1e8b9d10',
  String text = 'Call the bank',
  bool isArchived = false,
  String? archivedAt,
}) => {
  'id': id,
  'text': text,
  'isArchived': isArchived,
  'archivedAt': archivedAt,
  'createdAt': '2026-10-14T03:12:45.000000Z',
  'updatedAt': '2026-10-14T03:12:45.000000Z',
};

const _apiBase = 'http://test.local/api/v1';

RemoteTodoRepository _repo(_FakeAdapter adapter) => RemoteTodoRepository(
  dio: Dio()..httpClientAdapter = adapter,
  apiBase: _apiBase,
  token: 'secret',
);

void main() {
  test('getTodos unwraps the data envelope and parses todos', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'data': [_todoJson()],
      }),
    );

    final todos = await _repo(adapter).getTodos();

    expect(todos, hasLength(1));
    expect(todos.single.text, 'Call the bank');
    expect(todos.single.createdAt.isUtc, isTrue);
    expect(adapter.lastRequest!.path, '$_apiBase/todos');
  });

  test('getTodos omits the status query for the all filter', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': <dynamic>[]}));
    await _repo(adapter).getTodos();
    expect(adapter.lastRequest!.queryParameters, isEmpty);
  });

  test('getTodos sends the status query for a filtered read', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': <dynamic>[]}));
    await _repo(adapter).getTodos(filter: TodoFilter.archived);
    expect(adapter.lastRequest!.queryParameters, {'status': 'archived'});
  });

  test('sends the bearer token on every request', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': <dynamic>[]}));
    await _repo(adapter).getTodos();
    expect(adapter.lastRequest!.headers['Authorization'], 'Bearer secret');
  });

  test('createTodo sends the id when given one', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': _todoJson()}));
    await _repo(adapter).createTodo('Call the bank', id: 'fixed-id');
    expect(adapter.lastRequest!.data, {
      'text': 'Call the bank',
      'id': 'fixed-id',
    });
  });

  test('createTodo omits the id when not given one', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': _todoJson()}));
    await _repo(adapter).createTodo('  Trim me  ');
    expect(adapter.lastRequest!.data, {'text': 'Trim me'});
  });

  test('updateTodo sends only the fields provided', () async {
    final adapter = _FakeAdapter((_) async => _json({'data': _todoJson()}));
    await _repo(adapter).updateTodo('abc', isArchived: true);
    expect(adapter.lastRequest!.data, {'isArchived': true});
  });

  test('deleteTodo treats 404 as already gone', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'error': {'code': 'NOT_FOUND', 'message': 'todo not found'},
      }, 404),
    );
    await expectLater(_repo(adapter).deleteTodo('abc'), completes);
  });

  test('maps 401 to UnauthorizedFailure', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'error': {'code': 'UNAUTHORIZED', 'message': 'nope'},
      }, 401),
    );
    await expectLater(
      _repo(adapter).getTodos(),
      throwsA(isA<UnauthorizedFailure>()),
    );
  });

  test('maps 400 to ValidationFailure carrying the server message', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'text must be 1 to 500 characters',
        },
      }, 400),
    );
    await expectLater(
      _repo(adapter).createTodo(''),
      throwsA(
        isA<ValidationFailure>().having(
          (f) => f.message,
          'message',
          'text must be 1 to 500 characters',
        ),
      ),
    );
  });

  test('maps 429 to RateLimitedFailure', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'error': {'code': 'RATE_LIMITED', 'message': 'slow down'},
      }, 429),
    );
    await expectLater(
      _repo(adapter).getTodos(),
      throwsA(isA<RateLimitedFailure>()),
    );
  });

  test('maps an unreachable server to NetworkFailure', () async {
    final adapter = _FakeAdapter(
      (options) async => throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection refused',
      ),
    );
    await expectLater(
      _repo(adapter).getTodos(),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('maps 500 to ServerFailure', () async {
    final adapter = _FakeAdapter(
      (_) async => _json({
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
      }, 500),
    );
    await expectLater(_repo(adapter).getTodos(), throwsA(isA<ServerFailure>()));
  });
}
