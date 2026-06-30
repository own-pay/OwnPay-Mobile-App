import 'package:hive/hive.dart';

import '../../../core/config/app_config.dart';

/// On-device, user-controlled overrides for the server-supplied sender whitelist.
///
/// The user can locally DISABLE a whitelisted sender from the Settings screen. This is **strictly
/// subtractive**: a disabled sender is removed from the gate's effective whitelist, so the override can
/// only ever narrow what leaves the device — never add a sender the server didn't whitelist. That keeps
/// the privacy gate's fail-closed guarantee intact (SECURITY.md §2). Non-secret data, so it lives in the
/// shared settings Hive box (wiped on revoke), never in the keystore.
abstract interface class SenderOverrides {
  /// The set of locally-disabled senders, normalized to lowercase for case-insensitive matching.
  Future<Set<String>> disabled();

  /// Disables ([disabled] true) or re-enables ([disabled] false) a sender locally.
  Future<void> setDisabled(String sender, bool disabled);
}

/// Hive-backed [SenderOverrides], stored as a `List<String>` under [_key] in the settings box. The box
/// is opened lazily and cached; `Hive.initFlutter()` must have run first (done in `main`).
class HiveSenderOverrides implements SenderOverrides {
  HiveSenderOverrides();

  static const String _key = 'disabled_senders';

  Box<Object>? _cached;

  Future<Box<Object>> _openBox() async =>
      _cached ??= await Hive.openBox<Object>(AppConfig.boxSettings);

  @override
  Future<Set<String>> disabled() async {
    final Object? raw = (await _openBox()).get(_key);
    if (raw is List) {
      return raw.map((Object? e) => '${e ?? ''}'.trim().toLowerCase()).where((String s) => s.isNotEmpty).toSet();
    }
    return <String>{};
  }

  @override
  Future<void> setDisabled(String sender, bool disabled) async {
    final String key = sender.trim().toLowerCase();
    if (key.isEmpty) return;
    final Set<String> current = await this.disabled();
    if (disabled) {
      current.add(key);
    } else {
      current.remove(key);
    }
    await (await _openBox()).put(_key, current.toList());
  }
}
