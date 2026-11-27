import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// "Someone is at the gate" alerts for residents: a high-priority, call-style notification with sound and
/// vibration that can show full-screen over the lock screen. Tapping it opens the approval screen.
///
/// Works while the app is running or in the background (the live connection delivers the request).
/// To ring when the app is fully closed, add Firebase Cloud Messaging and call [visitorAtGate] from its handler.
class GateAlerts {
  GateAlerts._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Opens the approval screen for a visitor id (set by the app once the router exists).
  static void Function(String visitorId)? onOpen;

  static const _channel = AndroidNotificationChannel(
    'gate_requests',
    'Visitors at the gate',
    description: 'Rings when the guard asks you to approve a visitor.',
    importance: Importance.max,
  );

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) onOpen?.call(id);
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();
      _ready = true;
      // App started by tapping an alert while it was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final id = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && id != null && id.isNotEmpty) onOpen?.call(id);
    } catch (e) {
      debugPrint('GateAlerts init failed: $e');
    }
  }

  static int _idFor(String visitorId) => visitorId.hashCode & 0x7fffffff;

  /// Ring the resident: "Rohit is at the gate".
  static Future<void> visitorAtGate({required String visitorId, required String title, String body = ''}) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _idFor(visitorId),
        title: title,
        body: body.isEmpty ? 'Tap to allow or decline entry' : '$body · tap to allow or decline',
        payload: visitorId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            ticker: title,
            autoCancel: true,
            timeoutAfter: 120000,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 700, 500, 700, 500, 700, 500, 700]),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('GateAlerts show failed: $e');
    }
  }

  /// Remove the alert once the resident has answered (here or on another device).
  static Future<void> dismiss(String visitorId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idFor(visitorId));
    } catch (_) {}
  }
}
