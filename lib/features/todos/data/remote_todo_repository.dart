import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/todo.dart';
import '../domain/todo_repository.dart';

/// Talks to the Nudge backend described by `server/openapi.yaml`.
///
/// Every failure is translated into a typed [AppFailure] so nothing above the
/// data layer has to know about dio or HTTP status codes.
class RemoteTodoRepository implements TodoRepository {
  RemoteTodoRepository({
    required this._dio,
    required this._apiBase,
    required this._token,
  });

  final Dio _dio;
  final String _apiBase;
  final String _token;
  Options get _options => Options(headers: {'Authorization': 'Bearer $_token'});

  @override
  Future<List<Todo>> getTodos({TodoFilter filter = TodoFilter.all}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_apiBase/todos',
        queryParameters: filter == TodoFilter.all
            ? null
            : {'status': filter.name},
        options: _options,
      );
      return _unwrapList(response.data);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  @override
  Future<Todo> createTodo(String text, {String? id}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_apiBase/todos',
        data: {'text': text.trim(), 'id': ?id},
        options: _options,
      );
      return _unwrapTodo(response.data);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  @override
  Future<Todo> updateTodo(String id, {String? text, bool? isArchived}) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '$_apiBase/todos/$id',
        data: {'text': ?text?.trim(), 'isArchived': ?isArchived},
        options: _options,
      );
      return _unwrapTodo(response.data);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> deleteTodo(String id) async {
    try {
      await _dio.delete<void>('$_apiBase/todos/$id', options: _options);
    } on DioException catch (e) {
      // A 404 means it is already gone, which the contract treats as success.
      if (e.response?.statusCode == 404) return;
      throw _mapDioException(e);
    }
  }

  List<Todo> _unwrapList(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! List) {
      throw const ServerFailure('Unexpected response from the server.');
    }
    return data
        .map((item) => Todo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Todo _unwrapTodo(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw const ServerFailure('Unexpected response from the server.');
    }
    return Todo.fromJson(data);
  }

  AppFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure('The server took too long to respond.');
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Could not verify the server certificate.');
      case DioExceptionType.unknown:
        return e.error is SocketException
            ? const NetworkFailure()
            : const ServerFailure();
      case DioExceptionType.cancel:
        return const ServerFailure('Request cancelled.');
      case DioExceptionType.badResponse:
        break;
    }

    final status = e.response?.statusCode;
    return switch (status) {
      400 => ValidationFailure(
        _serverMessage(e) ?? 'The server rejected that.',
      ),
      401 => const UnauthorizedFailure(),
      404 => const NotFoundFailure(),
      429 => const RateLimitedFailure(),
      _ => const ServerFailure(),
    };
  }

  /// The contract's error envelope carries a developer-facing message.
  String? _serverMessage(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is Map) {
      final message = (body['error'] as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }
}
