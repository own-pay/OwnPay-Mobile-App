import 'package:equatable/equatable.dart';

/// Lifecycle of a queued SMS as it syncs to the server.
enum SyncStatus { pending, syncing, approved, failed }

/// A gate-passed SMS awaiting (or having completed) sync. Holds only the **encrypted** payload —
/// the plaintext body never reaches the queue.
class QueuedSms extends Equatable {
  const QueuedSms({
    required this.localId,
    required this.encryptedPayload,
    required this.sender,
    required this.receivedAt,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.failureReason,
    this.retryCount = 0,
    this.serverRef,
  });

  final int localId;
  final String encryptedPayload;
  final String sender;
  final DateTime receivedAt;
  final DateTime createdAt;
  final SyncStatus status;
  final String? failureReason;
  final int retryCount;
  final String? serverRef;

  /// Eligible for a sync attempt (pending or previously failed).
  bool get isSyncable => status == SyncStatus.pending || status == SyncStatus.failed;

  QueuedSms copyWith({
    SyncStatus? status,
    String? failureReason,
    int? retryCount,
    String? serverRef,
  }) =>
      QueuedSms(
        localId: localId,
        encryptedPayload: encryptedPayload,
        sender: sender,
        receivedAt: receivedAt,
        createdAt: createdAt,
        status: status ?? this.status,
        failureReason: failureReason ?? this.failureReason,
        retryCount: retryCount ?? this.retryCount,
        serverRef: serverRef ?? this.serverRef,
      );

  /// The wire shape for `POST /api/mobile/v1/sms`.
  Map<String, dynamic> toApi() => <String, dynamic>{
        'local_id': localId,
        'encrypted_payload': encryptedPayload,
        'sender': sender,
        'received_at': receivedAt.toIso8601String(),
      };

  /// Hive-friendly map (primitives only — avoids type adapters / codegen).
  Map<String, dynamic> toMap() => <String, dynamic>{
        'local_id': localId,
        'encrypted_payload': encryptedPayload,
        'sender': sender,
        'received_at': receivedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'status': status.index,
        'failure_reason': failureReason,
        'retry_count': retryCount,
        'server_ref': serverRef,
      };

  factory QueuedSms.fromMap(Map<String, dynamic> m) {
    final int statusIndex = m['status'] is int ? m['status'] as int : 0;
    return QueuedSms(
      localId: m['local_id'] is int ? m['local_id'] as int : int.parse('${m['local_id']}'),
      encryptedPayload: '${m['encrypted_payload']}',
      sender: '${m['sender']}',
      receivedAt: DateTime.tryParse('${m['received_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: SyncStatus.values[statusIndex.clamp(0, SyncStatus.values.length - 1)],
      failureReason: m['failure_reason'] as String?,
      retryCount: m['retry_count'] is int ? m['retry_count'] as int : 0,
      serverRef: m['server_ref'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [localId, encryptedPayload, sender, receivedAt, createdAt, status, failureReason, retryCount, serverRef];
}
