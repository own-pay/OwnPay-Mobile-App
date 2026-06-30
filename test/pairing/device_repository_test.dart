import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/features/pairing/data/device_repository.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';

class _MockDio extends Mock implements Dio {}

class _MockSecureStore extends Mock implements SecureStore {}

/// Builds the server's real success envelope: `Response::apiSuccess($data)` → `{success, data:{…}}`.
Response<dynamic> ok(Map<String, dynamic> data, {int status = 200}) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
      statusCode: status,
      data: <String, dynamic>{'success': true, 'data': data},
    );

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockDio dio;
  late _MockSecureStore store;
  late DeviceRepository repo;

  setUp(() {
    dio = _MockDio();
    store = _MockSecureStore();
    // Real ApiClient over a mocked Dio — exercises the actual response-normalization path.
    repo = DeviceRepository(ApiClient(dio), store);
  });

  group('pair', () {
    test('extracts tokens from the nested {success,data:{…}} envelope and stores them', () async {
      when(() => store.getOrCreateDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => store.saveCredentials(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            aesKey: any(named: 'aesKey'),
            serverUrl: any(named: 'serverUrl'),
            deviceUuid: any(named: 'deviceUuid'),
          )).thenAnswer((_) async {});
      when(() => dio.post<dynamic>(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async => ok(<String, dynamic>{
                'access_token': 'AT',
                'refresh_token': 'RT',
                'aes_key': 'KEYHEX',
                'device_uuid': 'UUID',
                'expires_in': 900,
              }, status: 201));

      final ApiResult<void> res =
          await repo.pair(serverUrl: 'https://srv.example', otp: '482910', deviceName: 'Pixel');

      expect(res.isOk, isTrue);
      verify(() => store.saveCredentials(
            accessToken: 'AT',
            refreshToken: 'RT',
            aesKey: 'KEYHEX',
            serverUrl: 'https://srv.example',
            deviceUuid: 'UUID',
          )).called(1);
    });

    test('a 4xx error surfaces as a Failure (error path unaffected by unwrapping)', () async {
      when(() => store.getOrCreateDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => dio.post<dynamic>(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 400,
          data: <String, dynamic>{'success': false, 'message': 'bad otp'},
        ),
        type: DioExceptionType.badResponse,
      ));

      final ApiResult<void> res =
          await repo.pair(serverUrl: 'https://srv.example', otp: 'bad', deviceName: 'Pixel');

      expect(res.isOk, isFalse);
      verifyNever(() => store.saveCredentials(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
            aesKey: any(named: 'aesKey'),
            serverUrl: any(named: 'serverUrl'),
            deviceUuid: any(named: 'deviceUuid'),
          ));
    });
  });

  group('refresh', () {
    test('rotates tokens AND sends the device fingerprint bound at pairing', () async {
      when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
      when(() => store.readRefreshToken()).thenAnswer((_) async => 'OLD_RT');
      // The same stable id sent as `device_id` at pairing; the server stored sha256(device_id) and
      // re-checks it on refresh, so refresh MUST send this or it 422s (FINGERPRINT_REQUIRED/MISMATCH).
      when(() => store.getOrCreateDeviceId()).thenAnswer((_) async => 'device-1');
      when(() => store.setAccessToken(any())).thenAnswer((_) async {});
      when(() => store.setRefreshToken(any())).thenAnswer((_) async {});
      when(() => dio.post<dynamic>(any(), data: any(named: 'data'), options: any(named: 'options')))
          .thenAnswer((_) async => ok(<String, dynamic>{
                'access_token': 'NEW_AT',
                'refresh_token': 'NEW_RT',
                'expires_in': 900,
              }));

      final bool refreshed = await repo.refresh();

      expect(refreshed, isTrue);
      verify(() => store.setAccessToken('NEW_AT')).called(1);
      verify(() => store.setRefreshToken('NEW_RT')).called(1);
      final Map<String, dynamic> body = verify(() => dio.post<dynamic>(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured.single as Map<String, dynamic>;
      expect(body['refresh_token'], 'OLD_RT');
      expect(body['fingerprint'], 'device-1');
    });
  });

  group('revoke', () {
    test('DELETEs this device (by its stored uuid) and returns Ok', () async {
      when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
      when(() => store.readDeviceUuid()).thenAnswer((_) async => 'uuid-1');
      when(() => dio.delete<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => ok(<String, dynamic>{'message': 'Device revoked'}));

      final ApiResult<void> res = await repo.revoke();

      expect(res.isOk, isTrue);
      final String url =
          verify(() => dio.delete<dynamic>(captureAny(), options: any(named: 'options'))).captured.single
              as String;
      expect(url, contains('/api/mobile/v1/devices/uuid-1'));
    });

    test('surfaces a failure when not paired (no server url)', () async {
      when(() => store.readServerUrl()).thenAnswer((_) async => null);

      final ApiResult<void> res = await repo.revoke();

      expect(res.isOk, isFalse);
      verifyNever(() => dio.delete<dynamic>(any(), options: any(named: 'options')));
    });
  });
}
