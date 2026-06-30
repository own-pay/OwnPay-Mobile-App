import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules.dart';
import 'package:ownpay_console/features/privacy_gate/domain/gate_decision.dart';
import 'package:ownpay_console/features/privacy_gate/domain/privacy_gate.dart';
import 'package:ownpay_console/shared/models/raw_sms.dart';

void main() {
  const gate = PrivacyGate();

  FilterRules rules({
    List<String> senders = const ['bKash', '16247', 'Nagad'],
    List<String> positive = const ['received', 'credited', 'TrxID', 'Tk'],
    List<String> negative = const ['OTP', 'PIN', 'verify', 'code'],
  }) =>
      FilterRules(
        version: 1,
        allowedSenders: senders,
        positiveKeywords: positive,
        negativeKeywords: negative,
        checkIntervalHours: 24,
        fetchedAt: DateTime(2026, 6, 23),
      );

  RawSms sms(String sender, String body) =>
      RawSms(sender: sender, body: body, receivedAt: DateTime(2026, 6, 23, 10, 30));

  group('PrivacyGate — fail-closed', () {
    test('null rules → dropped (noRules)', () {
      expect(gate.evaluate(sms('bKash', 'received Tk 100 TrxID X'), null).outcome,
          GateOutcome.droppedNoRules);
    });

    test('empty whitelist → dropped (noRules), even with a valid-looking message', () {
      final r = rules(senders: const []);
      expect(r.isFailClosed, isTrue);
      expect(gate.evaluate(sms('bKash', 'received Tk 100 TrxID X'), r).outcome,
          GateOutcome.droppedNoRules);
    });

    test('FilterRules.empty() is fail-closed', () {
      expect(FilterRules.empty().isFailClosed, isTrue);
    });
  });

  group('PrivacyGate — sender whitelist', () {
    test('unknown sender → dropped', () {
      expect(gate.evaluate(sms('SPAM-CO', 'received Tk 100 TrxID X'), rules()).outcome,
          GateOutcome.droppedSenderNotAllowed);
    });

    test('exact shortcode passes', () {
      expect(gate.evaluate(sms('16247', 'received Tk 500 TrxID 9A'), rules()).passed, isTrue);
    });

    test('sender match is case-insensitive', () {
      expect(gate.evaluate(sms('BKASH', 'credited Tk 500 TrxID 9A'), rules()).passed, isTrue);
    });

    test('substring sender id matches (alpha sender variants)', () {
      expect(gate.evaluate(sms('bKash-Alert', 'credited Tk 500 TrxID 9A'), rules()).passed, isTrue);
    });
  });

  group('PrivacyGate — negative keywords (highest priority)', () {
    test('OTP from a whitelisted sender is dropped', () {
      final d = gate.evaluate(sms('bKash', 'Your OTP is 123456'), rules());
      expect(d.outcome, GateOutcome.droppedNegativeKeyword);
      expect(d.matchedTerm, 'OTP');
    });

    test('negative keyword wins even when positive keywords are also present', () {
      // Contains both "TrxID"/"Tk" (positive) and "verify"/"code" (negative) → must drop.
      final d = gate.evaluate(
        sms('bKash', 'Use code to verify. You received Tk 100 TrxID 9A'),
        rules(),
      );
      expect(d.outcome, GateOutcome.droppedNegativeKeyword);
    });

    test('negative match is case-insensitive', () {
      expect(gate.evaluate(sms('Nagad', 'your otp: 9999'), rules()).outcome,
          GateOutcome.droppedNegativeKeyword);
    });
  });

  group('PrivacyGate — positive keywords', () {
    test('whitelisted sender without any positive keyword is dropped', () {
      expect(gate.evaluate(sms('bKash', 'Welcome to our service!'), rules()).outcome,
          GateOutcome.droppedNoPositiveKeyword);
    });

    test('positive keywords not enforced when the server configured none', () {
      final r = rules(positive: const []);
      expect(gate.evaluate(sms('bKash', 'anything at all'), r).passed, isTrue);
    });
  });

  group('PrivacyGate — pass', () {
    test('whitelisted + positive + no negative → pass', () {
      final d = gate.evaluate(sms('bKash', 'You have received Tk 1,500.00. TrxID 9F2K7Q1'), rules());
      expect(d.passed, isTrue);
      expect(d.outcome, GateOutcome.pass);
    });
  });

  group('FilterRules', () {
    test('parses API payload', () {
      final r = FilterRules.fromApi(<String, dynamic>{
        'version': 3,
        'allowed_senders': ['bKash', 16247],
        'positive_keywords': ['received'],
        'negative_keywords': ['OTP'],
        'check_interval_hours': 12,
      }, fetchedAt: DateTime(2026, 6, 23));
      expect(r.version, 3);
      expect(r.allowedSenders, ['bKash', '16247']); // numeric coerced to string
      expect(r.checkIntervalHours, 12);
      expect(r.isFailClosed, isFalse);
    });

    test('cache round-trip', () {
      final r = rules();
      final back = FilterRules.fromCache(r.toCache());
      expect(back.allowedSenders, r.allowedSenders);
      expect(back.negativeKeywords, r.negativeKeywords);
      expect(back.checkIntervalHours, r.checkIntervalHours);
    });

    test('isStale honours the interval', () {
      final r = FilterRules.fromApi(
        const <String, dynamic>{'check_interval_hours': 24, 'allowed_senders': ['bKash']},
        fetchedAt: DateTime(2026, 6, 23, 0, 0),
      );
      expect(r.isStale(DateTime(2026, 6, 23, 12, 0)), isFalse);
      expect(r.isStale(DateTime(2026, 6, 24, 1, 0)), isTrue);
    });
  });
}
