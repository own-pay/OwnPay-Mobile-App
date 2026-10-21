import '../../../shared/models/raw_sms.dart';
import 'filter_rules.dart';
import 'gate_decision.dart';

/// The on-device privacy gate — the compliance cornerstone.
///
/// Evaluation order (each step may DROP; only a full pass forwards the SMS):
///   1. **Fail-closed** — no rules / empty whitelist → drop.
///   2. **Sender whitelist** — sender not matched → drop.
///   3. **Negative keywords** — body contains a blocked term (OTP/PIN/verify/…) → drop,
///      *even from a whitelisted sender*.
///   4. **Positive keywords** — when configured, body must contain at least one → else drop.
///   5. **Pass.**
///
/// Matching is case-insensitive. A dropped message is never persisted, encrypted, or logged in full.
/// This class is pure (no I/O) so every branch is unit-tested.
class PrivacyGate {
  const PrivacyGate();

  GateDecision evaluate(RawSms sms, FilterRules? rules) {
    // 1. Fail-closed.
    if (rules == null || rules.isFailClosed) {
      return GateDecision.noRules;
    }

    final String sender = sms.sender.trim().toLowerCase();
    final String body = sms.body.toLowerCase();

    // 2. Sender whitelist — exact normalized match. The web parser uses the same contract, which
    // prevents the device from uploading a sender variant the server cannot parse with its template.
    final bool senderAllowed = rules.allowedSenders.any((String p) {
      final String pat = p.trim().toLowerCase();
      return pat.isNotEmpty && sender == pat;
    });
    if (!senderAllowed) {
      return GateDecision.senderNotAllowed;
    }

    // 3. Negative keywords — highest priority; drop even from a whitelisted sender.
    for (final String kw in rules.negativeKeywords) {
      final String k = kw.trim().toLowerCase();
      if (k.isNotEmpty && body.contains(k)) {
        return GateDecision.negativeKeyword(kw);
      }
    }

    // 4. Positive keywords — only enforced when the server configured any.
    if (rules.positiveKeywords.isNotEmpty) {
      final bool hasPositive = rules.positiveKeywords.any((String kw) {
        final String k = kw.trim().toLowerCase();
        return k.isNotEmpty && body.contains(k);
      });
      if (!hasPositive) {
        return GateDecision.noPositiveKeyword;
      }
    }

    // 5. Pass.
    return GateDecision.pass;
  }
}
