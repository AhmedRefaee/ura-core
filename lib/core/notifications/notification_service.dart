import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/app_logger.dart';

// Must be top-level — called by the OS when the app is terminated/backgrounded.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage msg) async {
  // The OS displays the notification automatically. No work needed here.
}

const _kChannelId   = 'ura_push_channel';
const _kChannelName = 'URA Notifications';

// Web push VAPID public key — get from Firebase Console →
// Project Settings → Cloud Messaging → Web Push certificates → Generate key pair
const _kVapidKey = 'BCw87gTfqprmmN07APrVRZnB2QrofdLsNIb_zpzDAnzrlndA_mwjHq6DMQz_AKpnGdOywOJtNblWrz-hdDZryH8';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  GoRouter? _router;
  bool _isRegistered = false;
  StreamSubscription? _foregroundSub;
  StreamSubscription? _tapSub;
  StreamSubscription? _tokenRefreshSub;

  void setRouter(GoRouter router) => _router = router;

  /// Called once in main() before runApp — sets up the Android channel
  /// and checks for a notification tap that cold-started the app.
  Future<void> init() async {
    if (!kIsWeb) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _local.initialize(
        settings: const InitializationSettings(android: androidSettings),
        onDidReceiveNotificationResponse: (details) {
          final route = details.payload;
          if (route != null && route.isNotEmpty) _router?.push(route);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _kChannelId,
            _kChannelName,
            description: 'Order and chat notifications for URA',
            importance: Importance.high,
          ));
      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleTap(initial);
    }
    // On web, flutter_local_notifications is not used.
    // FCM + firebase-messaging-sw.js handles browser notifications natively.
    logger.i('NotificationService → init complete');
  }

  /// Called after AuthAuthenticated is emitted — requests permission,
  /// saves the FCM token to user_devices, and wires up listeners.
  Future<void> registerForUser(String userId) async {
    logger.d('NotificationService → registerForUser: $userId');

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      logger.w('NotificationService → permission denied by user');
      return;
    }

    final token = await _fcm.getToken(vapidKey: kIsWeb ? _kVapidKey : null);
    if (token == null) {
      logger.w('NotificationService → FCM token is null');
      return;
    }

    await _saveToken(userId, token);

    if (!_isRegistered) {
      _tokenRefreshSub = _fcm.onTokenRefresh
          .listen((newToken) => _saveToken(userId, newToken));
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForeground);
      _tapSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      _isRegistered = true;
    }

    logger.i('NotificationService → registered for $userId');
  }

  /// Called in AuthCubit.signOut() BEFORE the Supabase sign-out so RLS
  /// still allows the delete on user_devices.
  Future<void> unregisterForUser(String userId) async {
    logger.d('NotificationService → unregisterForUser: $userId');

    _foregroundSub?.cancel();
    _tapSub?.cancel();
    _tokenRefreshSub?.cancel();
    _isRegistered = false;

    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _supabase.from('user_devices').delete().eq('fcm_token', token);
      }
      await _fcm.deleteToken();
    } catch (e) {
      // SERVICE_NOT_AVAILABLE or other transient FCM errors — safe to ignore
      // since subscriptions are already cancelled and sign-out will proceed.
      logger.e('NotificationService → FCM cleanup failed (non-critical)', error: e);
    }

    logger.i('NotificationService → unregistered');
  }

  Future<void> _saveToken(String userId, String token) async {
    logger.d('NotificationService → saving token');
    await _supabase.from('user_devices').upsert(
      {
        'user_id': userId,
        'fcm_token': token,
        'platform': kIsWeb ? 'web' : 'android',
        'last_seen_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'fcm_token',
    );
    logger.i('NotificationService → token saved');
  }

  void _handleForeground(RemoteMessage msg) {
    final notification = msg.notification;
    if (notification == null) return;
    logger.d('NotificationService → foreground: ${notification.title}');
    if (kIsWeb) return; // Service worker handles display on web.

    final route = msg.data['route'] as String? ?? '';
    final String? groupId;
    final String? groupKey;
    if (route.startsWith('/chat/')) {
      groupId = route.replaceFirst('/chat/', '');
      groupKey = 'chat_$groupId';
    } else if (route.startsWith('/order/')) {
      groupId = route.replaceFirst('/order/', '');
      groupKey = 'order_$groupId';
    } else {
      groupId = null;
      groupKey = null;
    }
    final notifId = groupId != null ? groupId.hashCode : msg.hashCode;

    // For order notifications, use BigTextStyle so swiping down the card
    // reveals the full status history while collapsed shows only the latest.
    final accumulatedBody = msg.data['accumulated_body'] as String?;
    final StyleInformation? style = (accumulatedBody != null &&
            accumulatedBody.contains('\n'))
        ? BigTextStyleInformation(accumulatedBody)
        : null;

    _local.show(
      id: notifId,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: groupKey,
          styleInformation: style,
        ),
      ),
      payload: route.isNotEmpty ? route : null,
    );
  }

  void _handleTap(RemoteMessage msg) {
    logger.d('NotificationService → tapped: ${msg.data}');
    final route = msg.data['route'] as String?;
    if (route != null && route.isNotEmpty) _router?.push(route);
  }
}
