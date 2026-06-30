import 'package:equatable/equatable.dart';

/// A device-scoped notification from `GET /api/mobile/v1/notifications` (id, type, title, body, time).
/// The payload blob is intentionally not modelled here — the poller only needs to display + acknowledge.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory AppNotification.fromApi(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    final int id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    return AppNotification(
      id: id,
      type: _str(json['type']),
      title: _str(json['title']),
      body: _str(json['body']),
      createdAt: DateTime.tryParse(_str(json['created_at'])) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;

  static String _str(Object? v) => v is String ? v : (v?.toString() ?? '');

  @override
  List<Object?> get props => <Object?>[id, type, title, body, createdAt];
}
