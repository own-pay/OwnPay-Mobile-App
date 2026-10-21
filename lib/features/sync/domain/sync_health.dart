import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// High-level state of the mobile-to-web SMS delivery worker.
enum SyncHealthStatus { unknown, idle, syncing, synced, receivedWithIssue, blocked, authRequired, failed }

class SyncHealthSnapshot extends Equatable {
  const SyncHealthSnapshot({
    this.status = SyncHealthStatus.unknown,
    this.message = 'Checking SMS delivery…',
    this.queuedCount = 0,
    this.failedCount = 0,
    this.lastAttemptAt,
    this.lastSuccessAt,
  });

  final SyncHealthStatus status;
  final String message;
  final int queuedCount;
  final int failedCount;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;

  SyncHealthSnapshot copyWith({
    SyncHealthStatus? status,
    String? message,
    int? queuedCount,
    int? failedCount,
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
  }) => SyncHealthSnapshot(
        status: status ?? this.status,
        message: message ?? this.message,
        queuedCount: queuedCount ?? this.queuedCount,
        failedCount: failedCount ?? this.failedCount,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      );

  @override
  List<Object?> get props => <Object?>[
        status,
        message,
        queuedCount,
        failedCount,
        lastAttemptAt,
        lastSuccessAt,
      ];
}

/// Read-only sync-health stream exposed by the queue worker.
abstract interface class SyncHealthSource {
  ValueListenable<SyncHealthSnapshot> get health;
}
