import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/privacy_gate/data/filter_rules_cache.dart';
import 'package:ownpay_console/features/privacy_gate/data/network_filter_rules_repository.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStore extends Mock implements SecureStore {}

/// In-memory [FilterRulesCache] so the repository can be tested without real Hive.
class _FakeCache implements FilterRulesCache {
  FilterRules? stored;
  int writes = 0;

  @override
  Future<FilterRules?> read() async => stored;

  @override
  Future<void> write(FilterRules rules) async {
    stored = rules;
    writes++;
  }
}

void main() {
  late _MockApiClient api;
  late _MockSecureStore store;
  late _FakeCache cache;

  // Fixed "now" so staleness is deterministic.
  DateTime now() => DateTime(2026, 6, 23, 12);

  NetworkFilterRulesRepository build() => NetworkFilterRulesRepository(api, store, cache, now);

  // ApiClient already unwraps the {success,data:{…}} envelope (see api_client_test.dart), so the repo
  // receives the rules object itself.
  Map<String, dynamic> rulesBody({List<String> senders = const <String>['bKash', '16247']}) =>
      <String, dynamic>{
        'version': 7,
        'updated_at': '2026-06-23T10:00:00Z',
        'allowed_senders': senders,
        'positive_keywords': <String>['received', 'TrxID'],
        'negative_keywords': <String>['OTP', 'PIN'],
        'check_interval_hours': 24,
      };

  FilterRules cachedRules({required DateTime fetchedAt, int interval = 24}) => FilterRules(
        version: 1,
        allowedSenders: const <String>['Nagad'],
        positiveKeywords: const <String>['credited'],
        negativeKeywords: const <String>['code'],
        checkIntervalHours: interval,
        fetchedAt: fetchedAt,
      );

  setUp(() {
    api = _MockApiClient();
    store = _MockSecureStore();
    cache = _FakeCache();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
  });

  test('fresh cache is returned without any network call', () async {
    cache.stored = cachedRules(fetchedAt: DateTime(2026, 6, 23, 6)); // 6h old, interval 24h → fresh

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNotNull);
    expect(result!.allowedSenders, <String>['Nagad']);
    verifyNever(() => api.get(any()));
  });

  test('missing cache → fetch, parse the (ApiClient-unwrapped) rules body, cache, return', () async {
    when(() => api.get(any())).thenAnswer((_) async => Ok<Map<String, dynamic>>(rulesBody()));

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNotNull);
    expect(result!.version, 7);
    expect(result.allowedSenders, <String>['bKash', '16247']);
    expect(result.negativeKeywords, contains('OTP'));
    // Cached for next time, stamped with the fetch clock.
    expect(cache.writes, 1);
    expect(cache.stored!.fetchedAt, now());
  });

  test('stale cache + fetch FAILS → fail-closed null (stale rules are NEVER served)', () async {
    cache.stored = cachedRules(fetchedAt: DateTime(2026, 6, 21, 0)); // >24h old → stale
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNull); // must NOT fall back to the stale cache
    expect(cache.writes, 0);
  });

  test('stale cache + fetch OK → returns the freshly fetched rules (not the stale ones)', () async {
    cache.stored = cachedRules(fetchedAt: DateTime(2026, 6, 21, 0)); // stale
    when(() => api.get(any())).thenAnswer((_) async => Ok<Map<String, dynamic>>(rulesBody()));

    final FilterRules? result = await build().effectiveRules();

    expect(result!.allowedSenders, <String>['bKash', '16247']); // fetched, not ['Nagad']
    expect(cache.writes, 1);
  });

  test('missing cache + no paired server → fail-closed null, no request attempted', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => null);

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNull);
    verifyNever(() => api.get(any()));
  });

  test('fetch returns a body without rule fields → fail-closed null (not cached as fresh-empty)', () async {
    when(() => api.get(any())).thenAnswer(
      (_) async => const Ok<Map<String, dynamic>>(<String, dynamic>{'success': true}),
    );

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNull);
    expect(cache.writes, 0);
  });

  test('first run (empty cache) offline → fail-closed null', () async {
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNull);
  });

  test('cached EMPTY whitelist is not served — re-checks and replaces it with real senders', () async {
    // A fresh-but-fail-closed cache (the server was misconfigured/empty at last fetch). It must NOT be
    // served as authoritative; the repo re-fetches and, now that senders exist, replaces it — so the
    // device recovers on the next drain instead of staying dark for the whole 24h interval.
    cache.stored = FilterRules(
      version: 1,
      allowedSenders: const <String>[], // empty → fail-closed
      positiveKeywords: const <String>[],
      negativeKeywords: const <String>[],
      checkIntervalHours: 24,
      fetchedAt: DateTime(2026, 6, 23, 6), // 6h old → "fresh" by interval, but unusable
    );
    when(() => api.get(any())).thenAnswer((_) async => Ok<Map<String, dynamic>>(rulesBody()));

    final FilterRules? result = await build().effectiveRules();

    expect(result!.allowedSenders, <String>['bKash', '16247']);
    expect(cache.writes, 1);
  });

  test('fetch returns an EMPTY whitelist → fail-closed null, not cached as fresh-empty', () async {
    when(() => api.get(any())).thenAnswer(
      (_) async => Ok<Map<String, dynamic>>(rulesBody(senders: const <String>[])),
    );

    final FilterRules? result = await build().effectiveRules();

    expect(result, isNull);
    expect(cache.writes, 0);
  });

  test('forceRefresh refetches even when the cache is fresh, and updates it', () async {
    cache.stored = cachedRules(fetchedAt: DateTime(2026, 6, 23, 6)); // fresh — effectiveRules would skip the net
    when(() => api.get(any())).thenAnswer((_) async => Ok<Map<String, dynamic>>(rulesBody()));

    final FilterRules? result = await build().forceRefresh();

    expect(result!.allowedSenders, <String>['bKash', '16247']); // fetched, not the cached ['Nagad']
    expect(cache.writes, 1);
    verify(() => api.get(any())).called(1);
  });

  test('forceRefresh that fails keeps the existing cache and returns null', () async {
    cache.stored = cachedRules(fetchedAt: DateTime(2026, 6, 23, 6));
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    final FilterRules? result = await build().forceRefresh();

    expect(result, isNull);
    expect(cache.writes, 0);
    expect(cache.stored!.allowedSenders, <String>['Nagad']); // untouched
  });
}
