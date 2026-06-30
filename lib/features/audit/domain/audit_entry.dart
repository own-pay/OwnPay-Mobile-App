import 'package:equatable/equatable.dart';

import '../../sync/domain/queued_sms.dart';

/// The user-facing audit row — a **metadata-only** projection of a [QueuedSms]. It deliberately omits
/// the encrypted payload (and the queue holds no plaintext at all), so the audit UI structurally cannot
/// render message contents — only sender, time, sync status, and the retry/failure metadata
/// (SECURITY.md §7 "metadata only", §9 "never display the encrypted payload").
class AuditEntry extends Equatable {
  const AuditEntry({
    required this.localId,
    required this.sender,
    required this.receivedAt,
    required this.status,
    required this.retryCount,
    this.failureReason,
    this.serverRef,
  });

  factory AuditEntry.fromQueued(QueuedSms q) => AuditEntry(
        localId: q.localId,
        sender: q.sender,
        receivedAt: q.receivedAt,
        status: q.status,
        retryCount: q.retryCount,
        failureReason: q.failureReason,
        serverRef: q.serverRef,
      );

  final int localId;
  final String sender;
  final DateTime receivedAt;
  final SyncStatus status;
  final int retryCount;
  final String? failureReason;
  final String? serverRef;

  bool get isSynced => status == SyncStatus.approved;
  bool get isIssue => status == SyncStatus.failed;

  @override
  List<Object?> get props =>
      <Object?>[localId, sender, receivedAt, status, retryCount, failureReason, serverRef];
}
