class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final String? type;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.type,
    this.isRead = false,
  });
}