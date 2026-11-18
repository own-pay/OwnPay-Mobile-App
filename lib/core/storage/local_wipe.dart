import 'package:hive/hive.dart';

import '../config/app_config.dart';
import 'secure_store.dart';

/// Wipes all local device data (SECURITY.md §8 "revoke & wipe"): clears platform secure storage (tokens,
/// AES key, server URL, device id) AND every app Hive box (queue + caches). After this the device is fully
/// unpaired with no recoverable secret material, and a subsequent pair rotates a fresh device id.
class LocalWipe {
  LocalWipe(this._store);

  final SecureStore _store;

  static const List<String> _boxes = <String>[
    AppConfig.boxSmsQueue,
    AppConfig.boxFilterRules,
    AppConfig.boxDashboardCache,
    AppConfig.boxAuditLog,
    AppConfig.boxSettings,
  ];

  /// Connection-only reset: deletes every secure-storage key (server URL, tokens, AES key,
  /// device id, SPKI pin) but keeps the Hive boxes (queue, filter-rules cache, dashboard
  /// cache, audit log, settings) intact. This is the recovery path when the server's
  /// certificate changed (e.g. renewed or re-keyed) — the user re-pairs against the new
  /// endpoint instead of doing a full wipe.
  Future<void> resetConnection() async {
    await _store.clear();
  }
  Future<void> wipe() async {
    await _store.clear();
    for (final String name in _boxes) {
      final Box<Object> box =
          Hive.isBoxOpen(name) ? Hive.box<Object>(name) : await Hive.openBox<Object>(name);
      await box.clear();
    }
  }
}
