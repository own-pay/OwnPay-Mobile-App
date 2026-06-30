import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.loading = true,
    this.snapshot,
    this.offline = false,
    this.failure,
    this.serverUrl,
  });

  final bool loading;
  final DashboardSnapshot? snapshot;

  /// True when [snapshot] is stale cached data served because the network was unavailable.
  final bool offline;

  /// Set only when there is no data at all to show.
  final Failure? failure;

  /// The paired server origin (for the "Active Host Node" header). Null until loaded / when unpaired.
  final String? serverUrl;

  bool get hasData => snapshot != null;

  /// Host portion of [serverUrl] for the header (e.g. `pay.example.com`), or '—' when unknown.
  String get serverHost {
    final String? url = serverUrl;
    if (url == null || url.isEmpty) return '—';
    final Uri? uri = Uri.tryParse(url);
    final String host = uri?.host ?? '';
    return host.isNotEmpty ? host : url;
  }

  DashboardState copyWith({
    bool? loading,
    DashboardSnapshot? snapshot,
    bool? offline,
    Failure? failure,
    String? serverUrl,
  }) =>
      DashboardState(
        loading: loading ?? this.loading,
        snapshot: snapshot ?? this.snapshot,
        offline: offline ?? this.offline,
        failure: failure ?? this.failure,
        serverUrl: serverUrl ?? this.serverUrl,
      );

  @override
  List<Object?> get props => <Object?>[loading, snapshot, offline, failure, serverUrl];
}

/// Loads and refreshes the dashboard, distinguishing fresh from cached (offline) data for the banner,
/// and surfaces the paired server host for the header.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, this._store) : super(const DashboardState());

  final DashboardRepository _repo;
  final SecureStore _store;

  Future<void> load() async {
    final String? serverUrl = await _store.readServerUrl();
    emit(state.copyWith(loading: true, serverUrl: serverUrl));
    final DashboardResult result = await _repo.load();
    switch (result) {
      case DashboardData(:final DashboardSnapshot snapshot, :final bool fromCache):
        emit(DashboardState(loading: false, snapshot: snapshot, offline: fromCache, serverUrl: serverUrl));
      case DashboardUnavailable(:final Failure failure):
        emit(DashboardState(loading: false, failure: failure, serverUrl: serverUrl));
    }
  }

  Future<void> refresh() => load();
}
