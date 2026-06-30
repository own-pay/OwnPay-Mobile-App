import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/notifications/data/network_notification_repository.dart';
import 'package:ownpay_console/features/notifications/domain/app_notification.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStore extends Mock implements SecureStore {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockApiClient api;
  late _MockSecureStore store;

  setUp(() {
    api = _MockApiClient();
    store = _MockSecureStore();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
  });

  NetworkNotificationRepository build() => NetworkNotificationRepository(api, store);

  test('fetch reads the data list (passed through by ApiClient) and parses notifications', () async {
    when(() => api.get(any())).thenAnswer((_) async => const Ok<Map<String, dynamic>>(<String, dynamic>{
          'success': true,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{'id': 1, 'type': 'payment', 'title': 'A', 'body': 'b', 'created_at': '2026-06-24T10:00:00Z'},
            <String, dynamic>{'id': 2, 'type': 'payment', 'title': 'C', 'body': 'd', 'created_at': '2026-06-24T11:00:00Z'},
          ],
        }));

    final List<AppNotification> list = await build().fetch();

    expect(list.map((AppNotification n) => n.id), <int>[1, 2]);
    expect(list.first.title, 'A');
  });

  test('fetch returns empty on a network error', () async {
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    expect(await build().fetch(), isEmpty);
  });

  test('fetch returns empty when not paired (no request made)', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => null);

    expect(await build().fetch(), isEmpty);
    verifyNever(() => api.get(any()));
  });

  test('acknowledge posts the handled ids', () async {
    when(() => api.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok<Map<String, dynamic>>(<String, dynamic>{'acknowledged': 2}));

    await build().acknowledge(<int>[1, 2]);

    final Map<String, dynamic> body =
        verify(() => api.post(any(), body: captureAny(named: 'body'))).captured.single as Map<String, dynamic>;
    expect(body['ids'], <int>[1, 2]);
  });

  test('acknowledge no-ops on an empty id list', () async {
    await build().acknowledge(const <int>[]);

    verifyNever(() => api.post(any(), body: any(named: 'body')));
  });
}
