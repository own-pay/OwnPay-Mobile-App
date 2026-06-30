import 'package:equatable/equatable.dart';

/// Lifecycle of a queued SMS as it syncs to the server. Serialized by name (not index), so the set
/// can evolve without corrupting already-stored rows.
enum SyncStatus { pending, approved, failed }

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
  ///
  /// `received_at` is serialized in **UTC** (trailing `Z`) — the device clock is local, and a naive
  /// local timestamp would be misread by the server (CLAUDE.md §5: ISO-8601 with timezone).
  Map<String, dynamic> toApi() => <String, dynamic>{
        'local_id': localId,
        'encrypted_payload': encryptedPayload,
        'sender': sender,
        'received_at': receivedAt.toUtc().toIso8601String(),
      };

  /// Hive-friendly map (primitives only — avoids type adapters / codegen).
  Map<String, dynamic> toMap() => <String, dynamic>{
        'local_id': localId,
        'encrypted_payload': encryptedPayload,
        'sender': sender,
        'received_at': receivedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'failure_reason': failureReason,
        'retry_count': retryCount,
        'server_ref': serverRef,
      };

  factory QueuedSms.fromMap(Map<String, dynamic> m) {
    return QueuedSms(
      localId: m['local_id'] is int ? m['local_id'] as int : int.parse('${m['local_id']}'),
      encryptedPayload: '${m['encrypted_payload']}',
      sender: '${m['sender']}',
      receivedAt: DateTime.tryParse('${m['received_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: _statusFromName(m['status']),
      failureReason: m['failure_reason'] as String?,
      retryCount: m['retry_count'] is int ? m['retry_count'] as int : 0,
      serverRef: m['server_ref'] as String?,
    );
  }

  /// Maps a stored status name back to the enum, defaulting to [SyncStatus.pending] for any
  /// missing/unknown value (so a row is re-synced rather than lost).
  static SyncStatus _statusFromName(Object? v) {
    final String name = '$v';
    for (final SyncStatus s in SyncStatus.values) {
      if (s.name == name) return s;
    }
    return SyncStatus.pending;
  }

  @override
  List<Object?> get props =>
      [localId, encryptedPayload, sender, receivedAt, createdAt, status, failureReason, retryCount, serverRef];
}
