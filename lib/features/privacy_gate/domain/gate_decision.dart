import 'package:equatable/equatable.dart';

/// Why the privacy gate let an SMS through or dropped it.
enum GateOutcome {
  pass,
  droppedNoRules,
  droppedSenderNotAllowed,
  droppedNegativeKeyword,
  droppedNoPositiveKeyword,
}

/// The result of evaluating one SMS against the [FilterRules].
///
/// [matchedTerm] carries the negative keyword that triggered a drop, for the metadata-only audit log.
/// It is never the message body.
class GateDecision extends Equatable {
  const GateDecision._(this.outcome, this.matchedTerm);

  final GateOutcome outcome;
  final String? matchedTerm;

  bool get passed => outcome == GateOutcome.pass;

  static const GateDecision pass = GateDecision._(GateOutcome.pass, null);
  static const GateDecision noRules = GateDecision._(GateOutcome.droppedNoRules, null);
  static const GateDecision senderNotAllowed = GateDecision._(GateOutcome.droppedSenderNotAllowed, null);
  static const GateDecision noPositiveKeyword = GateDecision._(GateOutcome.droppedNoPositiveKeyword, null);

  factory GateDecision.negativeKeyword(String term) =>
      GateDecision._(GateOutcome.droppedNegativeKeyword, term);

  /// Short, non-sensitive label for the audit log.
  String get auditLabel => switch (outcome) {
        GateOutcome.pass => 'forwarded',
        GateOutcome.droppedNoRules => 'ignored: no rules (fail-closed)',
        GateOutcome.droppedSenderNotAllowed => 'ignored: sender not whitelisted',
        GateOutcome.droppedNegativeKeyword => 'ignored: blocked keyword',
        GateOutcome.droppedNoPositiveKeyword => 'ignored: not a transaction',
      };

  @override
  List<Object?> get props => [outcome, matchedTerm];
}
