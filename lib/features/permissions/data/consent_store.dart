import 'package:hive/hive.dart';

import '../../../core/config/app_config.dart';

/// Persists one-time onboarding decisions that are **not secrets** — so they live in Hive, never in
/// the secure keystore (per CLAUDE.md §2.5, the keystore holds only tokens/keys).
///
/// Currently: whether the SMS prominent-disclosure step has been completed (by granting access or by
/// choosing "Not now"). Used to decide whether onboarding still needs to show the disclosure.
abstract interface class ConsentStore {
  Future<bool> isDisclosureCompleted();
  Future<void> markDisclosureCompleted();
}

/// Hive-backed [ConsentStore]. The box is opened lazily and cached; `Hive.initFlutter()` must have
/// run first (done in `main`).
class HiveConsentStore implements ConsentStore {
  HiveConsentStore();

  static const String _kDisclosureCompleted = 'disclosure_completed';

  Box<Object>? _cached;

  Future<Box<Object>> _openBox() async =>
      _cached ??= await Hive.openBox<Object>(AppConfig.boxSettings);

  @override
  Future<bool> isDisclosureCompleted() async {
    final Object? value = (await _openBox()).get(_kDisclosureCompleted);
    return value is bool && value;
  }

  @override
  Future<void> markDisclosureCompleted() async {
    await (await _openBox()).put(_kDisclosureCompleted, true);
  }
}
