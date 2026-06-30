import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/pairing/data/device_heartbeat.dart';

class _MockApi extends Mock implements ApiClient {}

class _MockStore extends Mock implements SecureStore {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockApi api;
  late _MockStore store;

  setUp(() {
    api = _MockApi();
    store = _MockStore();
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok<Map<String, dynamic>>(<String, dynamic>{'server_time': 't'}));
  });

  test('beat posts to /devices/heartbeat when paired', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');

    await DeviceHeartbeat(api, store).beat();

    verify(() => api.post('https://srv.example/api/mobile/v1/devices/heartbeats', body: any(named: 'body')))
        .called(1);
  });

  test('beat no-ops when not paired (no request made)', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => null);

    await DeviceHeartbeat(api, store).beat();

    verifyNever(() => api.post(any(), body: any(named: 'body')));
  });

  test('start sends an immediate beat', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');

    final DeviceHeartbeat hb = DeviceHeartbeat(api, store)..start();
    await pumpEventQueue();
    hb.stop();

    verify(() => api.post(any(), body: any(named: 'body'))).called(1);
  });
}
