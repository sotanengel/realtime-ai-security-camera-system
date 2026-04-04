import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../models/detection_event.dart';

/// 検知イベント通知サービス（F-040）
class NotificationService {
  NotificationService._();

  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();

  int _notificationId = 0;

  /// Frigateイベントの通知を送信する
  Future<void> notifyDetectionEvent(DetectionEvent event) async {
    final title = '${event.labelEmoji} ${_labelName(event.label)} を検知しました';
    final body =
        '${event.camera} | 信頼度: ${(event.score * 100).toStringAsFixed(0)}%'
        '${event.currentZones.isNotEmpty ? " | ${event.currentZones.join(", ")}" : ""}';

    await _showNotification(title: title, body: body);
  }

  /// on-device推論の検知通知を送信する
  Future<void> notifyLocalDetection(String label, double score) async {
    final emoji = _labelEmoji(label);
    final title = '$emoji $label をローカル検知しました';
    final body = '信頼度: ${(score * 100).toStringAsFixed(0)}%';

    await _showNotification(title: title, body: body);
  }

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'balcony_guard_channel',
      'ベランダ監視通知',
      channelDescription: '物体検知イベントの通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      _notificationId++,
      title,
      body,
      details,
    );
  }

  String _labelName(String label) {
    const names = {
      'person': '人',
      'bird': '鳥',
      'cat': '猫',
      'dog': '犬',
    };
    return names[label] ?? label;
  }

  String _labelEmoji(String label) {
    const emojis = {
      'person': '🧍',
      'bird': '🐦',
      'cat': '🐱',
      'dog': '🐕',
    };
    return emojis[label] ?? '📦';
  }
}
