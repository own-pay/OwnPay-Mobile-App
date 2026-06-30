import 'package:dio/dio.dart';

import '../error/failure.dart';
import 'api_result.dart';

/// Thin wrapper over Dio that returns [ApiResult] instead of throwing, and normalizes responses to
/// `Map<String, dynamic>`. Callers pass fully-qualified URLs (the server origin is per-user, set at
/// pairing). Authentication + 401 refresh are handled by the attached AuthInterceptor; pass
/// `auth: false` for the bootstrap (pair / refresh) calls.
///
/// **Response envelope:** every server success is `{ "success": true, "data": { … } }`
/// (`Response::apiSuccess`). This client unwraps `data` so callers receive the inner payload directly —
/// they must NOT re-read a `data` key. Error responses are non-2xx and surface as a [Failure].
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

  Future<ApiResult<Map<String, dynamic>>> delete(String url, {bool auth = true}) =>
      _send(() => _dio.delete<dynamic>(url, options: _options(auth)));

  Options _options(bool auth) => Options(extra: <String, dynamic>{'noAuth': !auth});

  Future<ApiResult<Map<String, dynamic>>> _send(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      final Response<dynamic> res = await run();
      return Ok<Map<String, dynamic>>(_unwrap(_asMap(res.data)));
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

  /// Unwraps the server's standard success envelope `{ "success": true, "data": { … } }` so callers
  /// receive the inner payload directly. Bodies without a `data` object — message-only successes, or
  /// list payloads carried under `data` — pass through unchanged (the caller reads `data` itself in the
  /// list case).
  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map<Object?, Object?>) {
      return data.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v));
    }
    return body;
  }

  Failure _mapError(DioException e) {
    final int? code = e.response?.statusCode;
    if (code == 401) {
      // A 401 that survives a SUCCESSFUL token refresh (flagged by AuthInterceptor) means the session is
      // alive but the retried request transiently failed — surface it as a retryable error so a blip
      // doesn't force a re-pair. A 401 with no recovery flag means the refresh itself failed → the
      // session is genuinely dead → AuthFailure (re-pair).
      if (e.requestOptions.extra['authRecovered'] == true) {
        return const ServerFailure(message: 'Temporary authorization error; will retry.', code: '401');
      }
      return const AuthFailure();
    }
    if (code != null && code >= 500) return ServerFailure(message: 'Server error ($code).', code: '$code');
    if (code != null && code >= 400) {
      final Object? data = e.response?.data;
      String message = 'The request was rejected.';
      if (data is Map<Object?, Object?>) {
        // The error envelope (`Response::apiError`) carries the human message at top-level `error`
        // (a string); `message` is tolerated as a fallback for any non-standard endpoint.
        final Object? serverMessage = data['error'] ?? data['message'];
        if (serverMessage is String && serverMessage.isNotEmpty) {
          message = serverMessage;
        }
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
