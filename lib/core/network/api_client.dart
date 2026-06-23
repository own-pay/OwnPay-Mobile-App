import 'package:dio/dio.dart';

import '../error/failure.dart';
import 'api_result.dart';

/// Thin wrapper over Dio that returns [ApiResult] instead of throwing, and normalizes responses to
/// `Map<String, dynamic>`. Callers pass fully-qualified URLs (the server origin is per-user, set at
/// pairing). Authentication + 401 refresh are handled by the attached AuthInterceptor; pass
/// `auth: false` for the bootstrap (pair / refresh) calls.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<ApiResult<Map<String, dynamic>>> post(
    String url, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) =>
      _send(() => _dio.post<dynamic>(url, data: body, options: _options(auth)));

  Future<ApiResult<Map<String, dynamic>>> get(String url, {bool auth = true}) =>
      _send(() => _dio.get<dynamic>(url, options: _options(auth)));

  Options _options(bool auth) => Options(extra: <String, dynamic>{'noAuth': !auth});

  Future<ApiResult<Map<String, dynamic>>> _send(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      final Response<dynamic> res = await run();
      return Ok<Map<String, dynamic>>(_asMap(res.data));
    } on DioException catch (e) {
      return Err<Map<String, dynamic>>(_mapError(e));
    } on Object {
      return const Err<Map<String, dynamic>>(UnknownFailure());
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map<Object?, Object?>) {
      return data.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v));
    }
    return <String, dynamic>{};
  }

  Failure _mapError(DioException e) {
    final int? code = e.response?.statusCode;
    if (code == 401) return const AuthFailure();
    if (code != null && code >= 500) return ServerFailure(message: 'Server error ($code).', code: '$code');
    if (code != null && code >= 400) {
      final Object? data = e.response?.data;
      String message = 'The request was rejected.';
      if (data is Map<Object?, Object?> && data['message'] is String) {
        message = data['message'] as String;
      }
      return ValidationFailure(message: message, code: '$code');
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure(message: 'The server certificate could not be verified.');
      default:
        return const UnknownFailure();
    }
  }
}
