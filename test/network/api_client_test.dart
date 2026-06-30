import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> resp(Object? data, {int status = 200}) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
      statusCode: status,
      data: data,
    );

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late _MockDio dio;
  late ApiClient api;

  setUp(() {
    dio = _MockDio();
    api = ApiClient(dio);
  });

  void stubGet(Response<dynamic> response) {
    when(() => dio.get<dynamic>(any(), options: any(named: 'options')))
        .thenAnswer((_) async => response);
  }

  test('unwraps the {success,data:{…}} envelope to the inner object', () async {
    stubGet(resp(<String, dynamic>{
      'success': true,
      'data': <String, dynamic>{'access_token': 'AT', 'expires_in': 900},
    }));

    final result = await api.get('https://srv/x');

    expect(result.valueOrNull, <String, dynamic>{'access_token': 'AT', 'expires_in': 900});
  });

  test('passes a message-only success (no data object) through unchanged', () async {
    stubGet(resp(<String, dynamic>{'success': true}));

    final result = await api.get('https://srv/x');

    expect(result.valueOrNull, <String, dynamic>{'success': true});
  });

  test('does not unwrap when data is a list — caller reads data itself', () async {
    stubGet(resp(<String, dynamic>{
      'success': true,
      'data': <dynamic>[
        <String, dynamic>{'id': 1},
      ],
    }));

    final result = await api.get('https://srv/x');

    expect(result.valueOrNull!['data'], isA<List<dynamic>>());
  });

  test('unwrapping also applies to POST', () async {
    when(() => dio.post<dynamic>(any(), data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => resp(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'revoked': 3},
            }));

    final result = await api.post('https://srv/x', body: <String, dynamic>{'ids': <int>[]});

    expect(result.valueOrNull, <String, dynamic>{'revoked': 3});
  });

  group('error mapping', () {
    DioException dioError(int status, Object? data) => DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response<dynamic>(requestOptions: RequestOptions(path: '/'), statusCode: status, data: data),
          type: DioExceptionType.badResponse,
        );

    Failure? failureOf(ApiResult<Map<String, dynamic>> result) =>
        result.fold<Failure?>((Failure f) => f, (Map<String, dynamic> _) => null);

    test('a 4xx surfaces the server `error` message as a ValidationFailure', () async {
      when(() => dio.get<dynamic>(any(), options: any(named: 'options'))).thenThrow(
        dioError(422, <String, dynamic>{
          'success': false,
          'error': 'pairing_code and device_id required',
          'errors': <dynamic>[
            <String, dynamic>{'code': 'PAIRING_PARAMETERS_REQUIRED'},
          ],
        }),
      );

      final result = await api.get('https://srv/x');
      final Failure? failure = failureOf(result);

      expect(failure, isA<ValidationFailure>());
      expect(failure!.message, 'pairing_code and device_id required');
    });

    test('a 401 maps to AuthFailure (drives the re-pair flow)', () async {
      when(() => dio.get<dynamic>(any(), options: any(named: 'options'))).thenThrow(dioError(401, null));

      expect(failureOf(await api.get('https://srv/x')), isA<AuthFailure>());
    });

    test('a 401 AFTER a successful refresh is retryable (ServerFailure), NOT a dead session', () async {
      // AuthInterceptor flags a post-refresh retry 401 with extra[authRecovered]=true: the refresh token
      // still works (session alive), so a transient retry blip must not force a re-pair (→ /pair).
      final RequestOptions opts = RequestOptions(path: '/', extra: <String, dynamic>{'authRecovered': true});
      when(() => dio.get<dynamic>(any(), options: any(named: 'options'))).thenThrow(
        DioException(
          requestOptions: opts,
          response: Response<dynamic>(requestOptions: opts, statusCode: 401, data: null),
          type: DioExceptionType.badResponse,
        ),
      );

      final Failure? failure = failureOf(await api.get('https://srv/x'));
      expect(failure, isA<ServerFailure>());
      expect(failure, isNot(isA<AuthFailure>()));
    });

    test('a 5xx maps to ServerFailure (retryable)', () async {
      when(() => dio.get<dynamic>(any(), options: any(named: 'options'))).thenThrow(dioError(503, null));

      expect(failureOf(await api.get('https://srv/x')), isA<ServerFailure>());
    });
  });
}
