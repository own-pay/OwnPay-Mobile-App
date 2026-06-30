import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

/// [NotificationRepository] over `GET /notifications` + `POST /notifications/acknowledgements`. The list
/// endpoint returns `data` as a JSON array, which `ApiClient` passes through unchanged — so [fetch] reads
/// `body['data']` directly.
class NetworkNotificationRepository implements NotificationRepository {
  NetworkNotificationRepository(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  @override
  Future<List<AppNotification>> fetch() async {
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      return const <AppNotification>[];
    }
    final ApiResult<Map<String, dynamic>> res =
        await _api.get('$base${AppConfig.apiPrefix}/notifications');
    return res.fold<List<AppNotification>>(
      (_) => const <AppNotification>[],
      (Map<String, dynamic> body) => _parse(body['data']),
    );
  }

  @override
  Future<void> acknowledge(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      return;
    }
    await _api.post(
      '$base${AppConfig.apiPrefix}/notifications/acknowledgements',
      body: <String, dynamic>{'ids': ids},
    );
  }

  List<AppNotification> _parse(Object? data) {
    if (data is List) {
      return data
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) => AppNotification.fromApi(
                m.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v)),
              ))
          .toList();
    }
    return const <AppNotification>[];
  }
}
