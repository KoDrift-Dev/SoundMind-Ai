import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/app_notification.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> init() async {
    if (_isInitialized) return;

    const androidInitialize = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidInitialize);
    
    try {
      await _localNotifications.initialize(settings: initializationSettings);
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  void add(String title, String message, {String? type}) async {
    _notifications.insert(0, AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      timestamp: DateTime.now(),
      type: type,
    ));
    notifyListeners();

    try {
      if (!_isInitialized) await init();

      // Show OS Notification on device
      const androidDetails = AndroidNotificationDetails(
        'soundmind_general',
        'SoundMind AI Music',
        channelDescription: 'Notifications for recommendations, mixes, and errors',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const details = NotificationDetails(android: androidDetails);
      
      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: message,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('NotificationService OS show error: $e');
    }
  }

  void addRecommendation(String title, String message, {String type = 'recommendation'}) {
    final now = DateTime.now();
    final duplicate = _notifications.any(
      (n) => n.title == title && now.difference(n.timestamp).inMinutes < 20,
    );
    if (!duplicate) {
      add(title, message, type: type);
    }
  }

  void addError(String title, String message) {
    final now = DateTime.now();
    final duplicate = _notifications.any(
      (n) => n.title == title && now.difference(n.timestamp).inMinutes < 5,
    );
    if (!duplicate) {
      add(title, message, type: 'error');
    }
  }

  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index].isRead = true;
      notifyListeners();
    }
  }

  void markAllAsRead() {
    bool changed = false;
    for (var n in _notifications) {
      if (!n.isRead) {
        n.isRead = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void clearAll() {
    if (_notifications.isNotEmpty) {
      _notifications.clear();
      notifyListeners();
    }
  }
}