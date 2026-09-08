import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'download_models.dart';

/// Notification manager for persistent download progress, completion, and failure alerts.
class DownloadNotificationService {
  DownloadNotificationService._internal();
  static final DownloadNotificationService instance =
      DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int ongoingNotificationId = 9999;
  static const String channelId = 'soundmind_downloads';
  static const String channelName = 'SoundMind Downloads';
  static const String channelDescription =
      'Real-time progress and notifications for audio downloads';

  static const String payloadViewDownloads = 'view_downloads';

  /// Callback registered by app navigation to open the Downloads screen.
  static void Function()? onViewDownloadsRequested;

  bool _initialized = false;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload ?? response.actionId;
          if (payload == payloadViewDownloads) {
            onViewDownloadsRequested?.call();
          }
        },
      );

      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.low,
            showBadge: false,
          ),
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('DownloadNotificationService init error: $e');
    }
  }

  /// Updates or shows the persistent ongoing notification for active downloads.
  Future<void> showOrUpdateProgress(List<DownloadTask> activeTasks) async {
    if (!_initialized) await init();

    if (activeTasks.isEmpty) {
      await dismissProgress();
      return;
    }

    // Rate-limit notifications to at most 1 update every 600ms to avoid Android notification throttling
    final now = DateTime.now();
    if (now.difference(_lastProgressUpdate).inMilliseconds < 600) {
      return;
    }
    _lastProgressUpdate = now;

    try {
      final task = activeTasks.first;
      final int activeCount = activeTasks.length;

      final String title;
      final String body;
      final int percent;

      if (activeCount == 1) {
        title = task.title;
        if (task.status == DownloadStatus.converting) {
          body = 'Converting to ${task.outputFormat.toUpperCase()}...';
          percent = 95;
        } else {
          final progressStr = task.formattedProgress;
          body = 'Downloading… $progressStr';
          percent = (task.progress * 100).clamp(0, 100).toInt();
        }
      } else {
        title = '$activeCount downloads in progress';
        final totalProgress = activeTasks.fold<double>(
              0.0,
              (sum, t) => sum + t.progress,
            ) /
            activeCount;
        percent = (totalProgress * 100).clamp(0, 100).toInt();
        body = '${task.title} and ${activeCount - 1} more';
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        autoCancel: false,
        showProgress: true,
        maxProgress: 100,
        progress: percent,
        icon: '@mipmap/ic_launcher',
        actions: const [
          AndroidNotificationAction(
            payloadViewDownloads,
            'View',
            showsUserInterface: true,
          ),
        ],
      );

      final details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: ongoingNotificationId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payloadViewDownloads,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showProgress error: $e');
    }
  }

  /// Shows a short-lived, dismissible notification when a download completes.
  Future<void> showCompleted(DownloadTask task) async {
    if (!_initialized) await init();

    try {
      final notificationId =
          task.videoId.hashCode.abs().remainder(100000) + 1000;

      final androidDetails = AndroidNotificationDetails(
        'soundmind_general',
        'SoundMind AI Music',
        channelDescription: 'Notifications for completed downloads',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
        actions: const [
          AndroidNotificationAction(
            payloadViewDownloads,
            'View',
            showsUserInterface: true,
          ),
        ],
      );

      final details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: notificationId,
        title: 'Download complete',
        body: '${task.title} • ${task.outputFormat.toUpperCase()}',
        notificationDetails: details,
        payload: payloadViewDownloads,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showCompleted error: $e');
    }
  }

  /// Shows a dismissible failure notification with a retry action.
  Future<void> showFailed(DownloadTask task) async {
    if (!_initialized) await init();

    try {
      final notificationId =
          task.videoId.hashCode.abs().remainder(100000) + 2000;

      final androidDetails = AndroidNotificationDetails(
        'soundmind_general',
        'SoundMind AI Music',
        channelDescription: 'Notifications for failed downloads',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
        actions: const [
          AndroidNotificationAction(
            payloadViewDownloads,
            'View',
            showsUserInterface: true,
          ),
        ],
      );

      final details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: notificationId,
        title: 'Download failed',
        body: '${task.title}: ${task.errorMessage ?? 'Download error'}',
        notificationDetails: details,
        payload: payloadViewDownloads,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showFailed error: $e');
    }
  }

  /// Dismisses the ongoing progress notification.
  Future<void> dismissProgress() async {
    try {
      await _notificationsPlugin.cancel(id: ongoingNotificationId);
    } catch (e) {
      debugPrint('DownloadNotificationService dismissProgress error: $e');
    }
  }
}
