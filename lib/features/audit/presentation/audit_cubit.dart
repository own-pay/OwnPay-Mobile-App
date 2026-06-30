import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../sync/domain/sms_queue_store.dart';
import '../../sync/domain/syncer.dart';
import '../data/sms_body_revealer.dart';
import '../domain/audit_entry.dart';

/// Which slice of the audit trail is shown.
enum AuditFilter { all, synced, issues }

class AuditState extends Equatable {
  const AuditState({
    this.loading = true,
    this.entries = const <AuditEntry>[],
    this.filter = AuditFilter.all,
  });

  final bool loading;
  final List<AuditEntry> entries;
  final AuditFilter filter;

  /// Entries matching the active [filter] (Issues = failed; Synced = approved).
  List<AuditEntry> get visible {
    switch (filter) {
      case AuditFilter.all:
        return entries;
      case AuditFilter.synced:
        return entries.where((AuditEntry e) => e.isSynced).toList();
      case AuditFilter.issues:
        return entries.where((AuditEntry e) => e.isIssue).toList();
    }
  }

  int get failedCount => entries.where((AuditEntry e) => e.isIssue).length;

  AuditState copyWith({bool? loading, List<AuditEntry>? entries, AuditFilter? filter}) => AuditState(
        loading: loading ?? this.loading,
        entries: entries ?? this.entries,
        filter: filter ?? this.filter,
      );

  @override
  List<Object?> get props => <Object?>[loading, entries, filter];
}

/// Drives the audit-trail screen: reads the offline queue as **metadata-only** [AuditEntry]s, exposes
/// the All|Synced|Issues filter, and the "clear failed" / "retry now" actions. The [AuditEntry] list
/// never carries the payload (see [AuditEntry]); the body is decrypted on demand via [revealBody] only
/// when the owner taps a row.
class AuditCubit extends Cubit<AuditState> {
  AuditCubit(this._queue, this._sync, this._revealer) : super(const AuditState());

  final SmsQueueStore _queue;
  final Syncer _sync;
  final SmsBodyRevealer _revealer;

  Future<void> load() async {
    final List<AuditEntry> entries = (await _queue.all()).map(AuditEntry.fromQueued).toList()
      ..sort((AuditEntry a, AuditEntry b) => b.localId.compareTo(a.localId)); // newest first
    emit(state.copyWith(loading: false, entries: entries));
  }

  void setFilter(AuditFilter filter) => emit(state.copyWith(filter: filter));

  /// Removes the failed rows the user chose to clear, then refreshes.
  Future<void> clearFailed() async {
    await _queue.deleteFailed();
    await load();
  }

  /// Revives any exhausted failed rows, kicks an immediate sync attempt, then refreshes to reflect new
  /// statuses. The reset is what lets a user-initiated retry re-deliver rows that had hit `maxRetries`.
  Future<void> retryNow() async {
    await _queue.resetFailedForRetry();
    await _sync.syncNow(force: true);
    await load();
  }

  /// Decrypts the SMS body for [localId] for on-screen display (owner-only). Null when it can't be shown.
  Future<String?> revealBody(int localId) => _revealer.reveal(localId);
}
