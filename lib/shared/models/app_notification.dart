class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? actionRoute;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.actionRoute,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        actionRoute: m['action_route'] as String?,
        isRead: m['is_read'] as bool,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
