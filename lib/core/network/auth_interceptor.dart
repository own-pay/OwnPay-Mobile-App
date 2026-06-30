import 'package:dio/dio.dart';

import '../storage/secure_store.dart';

/// Attaches the bearer access token and performs a single-flight refresh on 401.
///
/// On 401 (not a bootstrap call, not already retried) it calls [onRefresh] once — concurrent 401s
/// share the same in-flight refresh — then replays the original request with the rotated token. If
/// refresh fails, the original 401 propagates so the caller can surface an [AuthFailure] → re-pair.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._dio, this._onRefresh);

  final SecureStore _store;
  final Dio _dio;
  final Future<bool> Function() _onRefresh;

  Future<bool>? _inFlightRefresh;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['noAuth'] != true) {
      final String? token = await _store.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final bool isAuthError = err.response?.statusCode == 401;
    final bool noAuth = err.requestOptions.extra['noAuth'] == true;
    final bool alreadyRetried = err.requestOptions.extra['retried'] == true;

    if (!isAuthError || noAuth || alreadyRetried) {
      handler.next(err);
      return;
    }

    final bool refreshed = await _refreshOnce();
    if (!refreshed) {
      handler.next(err); // bubbles up as AuthFailure → re-pair flow
      return;
    }

    final String? token = await _store.readAccessToken();
    final RequestOptions retryOptions = err.requestOptions
      ..extra['retried'] = true
      ..headers['Authorization'] = 'Bearer $token';

    try {
      final Response<dynamic> response = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      // The refresh SUCCEEDED — the refresh token is valid, so the session is alive. The retried request
      // failing anyway (e.g. a transient 401 during the startup request burst) must NOT be escalated to a
      // dead-session re-pair: mark it so the client maps it to a retryable error instead of AuthFailure.
      // Otherwise a one-off blip strands the user on the re-pair screen even though their session is fine.
      retryError.requestOptions.extra['authRecovered'] = true;
      handler.next(retryError);
    }
  }

  Future<bool> _refreshOnce() {
    return _inFlightRefresh ??= _onRefresh().whenComplete(() => _inFlightRefresh = null);
  }
}
