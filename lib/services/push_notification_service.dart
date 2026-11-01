import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Top-level handler for FCM background messages (must be a top-level function).
/// Called by the OS when an FCM message arrives while the app is killed/backgrounded.
/// IMPORTANT: Must call Firebase.initializeApp() because this runs in its own isolate.
/// On stock Android, notification-payload messages are auto-displayed, but many
/// OEM ROMs (Samsung, Xiaomi, Huawei, Oppo) aggressively suppress them.
/// To guarantee delivery, we explicitly display via flutter_local_notifications.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Firebase must be initialized in the background isolate
    await Firebase.initializeApp();

    if (kDebugMode) {
      print('[FCM_BG] Background message received: ${message.messageId}');
      print('[FCM_BG] Data: ${message.data}');
    }

    // Extract title/body from data payload (data-only FCM messages).
    // The Edge Function sends title/body in the `data` map so that
    // onBackgroundMessage always fires and we have full display control.
    final title = message.data['title'] ??
        message.notification?.title ??
        'New Notification';
    final body = message.data['body'] ??
        message.data['message'] ??
        message.notification?.body ??
        'You have a new notification';
    final notificationType = message.data['notification_type'] ?? 'general';

    // Initialize flutter_local_notifications in this background isolate
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await localNotifications.initialize(settings: initSettings);

    // Determine the correct notification channel based on type
    String channelId = 'fcm_notifications';
    String channelName = 'Push Notifications';
    Importance importance = Importance.high;
    if ([
      'banking_details_added',
      'subaccount_approval_required',
      'partner_approved'
    ].contains(notificationType)) {
      channelId = 'admin_alerts';
      channelName = 'Admin Alerts';
      importance = Importance.max;
    } else if (notificationType == 'deal_request') {
      channelId = 'deal_requests';
      channelName = 'Deal Requests';
    } else if ([
      'deal_approved',
      'pos_deal_approved',
      'deal_rejected',
      'deal_cancelled'
    ].contains(notificationType)) {
      channelId = 'deal_responses';
      channelName = 'Deal Responses';
    } else if (['payment_received', 'payment_success']
        .contains(notificationType)) {
      channelId = 'payment_notifications';
      channelName = 'Payment Notifications';
    } else if (notificationType.startsWith('deal')) {
      channelId = 'deal_notifications';
      channelName = 'Deal Notifications';
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: importance,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );

    if (kDebugMode) {
      print('[FCM_BG] Notification displayed: $title');
    }
  } catch (e) {
    if (kDebugMode) {
      print('[FCM_BG] Background handler error: $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _notificationSubscription;
  final Logger _logger = Logger();

  // Track notification IDs that have already been shown as local push notifications
  final Set<String> _shownNotificationIds = {};

  // Callback for UI updates
  Function? onNotificationsChanged;

  Future<void> initialize() async {
    // Skip notification initialization on Windows (not supported)
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (kDebugMode) {
        print('PushNotificationService: Skipping initialization on Windows');
      }
      // Still set up realtime subscription for notifications
      _setupRealtimeNotifications();
      return;
    }

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
    );

    // Pre-create all notification channels so FCM push notifications
    // work even when the app is killed/backgrounded. Without this,
    // Android silently drops FCM notifications targeting a channel
    // that hasn't been created yet.
    await _createNotificationChannels();

    // Set up Firebase Cloud Messaging for push notifications when app is closed
    await _initializeFCM();

    // Set up realtime subscription for notifications
    _setupRealtimeNotifications();
  }

  /// Create all notification channels up-front so that FCM push
  /// notifications arriving while the app is killed/backgrounded can be
  /// displayed. On Android 8+, a notification targeting a non-existent
  /// channel is silently dropped.
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const channels = [
      AndroidNotificationChannel(
        'deal_responses',
        'Deal Responses',
        description: 'Notifications when businesses approve or reject your deal requests',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'deal_requests',
        'Deal Requests',
        description: 'Notifications when members request deals from your business',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'deal_notifications',
        'Deal Notifications',
        description: 'Notifications for deal authorizations and updates',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'payment_notifications',
        'Payment Notifications',
        description: 'Notifications for successful payments and receipts',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'admin_alerts',
        'Admin Alerts',
        description: 'Critical alerts for administrators requiring immediate attention',
        importance: Importance.max,
      ),
      AndroidNotificationChannel(
        'fcm_notifications',
        'Push Notifications',
        description: 'Notifications received via push when app is in foreground',
        importance: Importance.high,
      ),
    ];

    for (final channel in channels) {
      await androidPlugin.createNotificationChannel(channel);
    }
    _logger.i('All notification channels created');
  }

  /// Initialize Firebase Cloud Messaging - handles push notifications when app
  /// is killed or in the background.
  Future<void> _initializeFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permissions (required for iOS, Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _logger.w('FCM: Push notification permissions denied by user');
        return;
      }

      _logger.i('FCM: Permission status: ${settings.authorizationStatus}');

      // iOS: Ensure notification banners/alerts/sounds are shown even when
      // the app is in the foreground. Without this, iOS silently suppresses
      // FCM notification-payload messages while the app is active.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get and store the FCM token
      await _updateFcmToken();

      // Listen for token refreshes (token can change when app is reinstalled,
      // user clears data, or the server rotates tokens)
      messaging.onTokenRefresh.listen((newToken) {
        _logger.i('FCM: Token refreshed');
        _storeFcmToken(newToken);
      });

      // Handle the notification that launched the app from a TERMINATED state.
      // This is critical: without it, tapping a push notification while the
      // app is fully killed would not trigger any in-app handling.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _logger.i('FCM: App launched from terminated state via notification: '
            '${initialMessage.notification?.title}');
        // Trigger UI refresh after a short delay to let the widget tree build
        Future.delayed(const Duration(seconds: 2), () {
          if (onNotificationsChanged != null) {
            onNotificationsChanged!();
          }
        });
      }

      // Handle foreground FCM messages - show as local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _logger.d('FCM: Foreground message received: ${message.notification?.title}');
        // Show notification from either notification payload or data payload
        if (message.notification != null) {
          _showFcmNotificationLocally(message);
        } else if (message.data.isNotEmpty) {
          // Data-only message — still display it
          _showFcmDataNotificationLocally(message);
        }
      });

      // Handle notification taps when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _logger.d('FCM: App opened from notification: ${message.notification?.title}');
        // Trigger UI refresh so the user sees updated notifications
        if (onNotificationsChanged != null) {
          onNotificationsChanged!();
        }
      });

      // Request battery optimization exemption on Android
      // Many OEMs (Samsung, Xiaomi, Huawei, Oppo, etc.) aggressively kill
      // background processes including FCM, preventing push delivery.
      await _requestBatteryOptimizationExemption();
    } catch (e) {
      _logger.e('FCM: Failed to initialize: $e');
    }
  }

  /// Get the current FCM token and store it in Supabase profiles table.
  Future<void> _updateFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _storeFcmToken(token);
      }
    } catch (e) {
      _logger.e('FCM: Failed to get/store token: $e');
    }
  }

  /// Store the FCM token in the user's profile row so the Edge Function can
  /// look it up when sending push notifications.
  Future<void> _storeFcmToken(String token) async {
    try {
      final user = SupabaseService.instance.getCurrentUser();
      if (user == null) return;

      await SupabaseService.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);

      _logger.i('FCM: Token stored for user ${user.id}');
    } catch (e) {
      _logger.e('FCM: Failed to store token: $e');
    }
  }

  /// Show a foreground FCM message as a local notification (since FCM
  /// notification payloads are NOT auto-displayed when the app is in
  /// the foreground).
  Future<void> _showFcmNotificationLocally(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'fcm_notifications',
      'Push Notifications',
      channelDescription: 'Notifications received via push when app is in foreground',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: notification.title ?? 'New Notification',
      body: notification.body ?? '',
      notificationDetails: notificationDetails,
    );
  }

  /// Show a data-only FCM message as a local notification.
  /// Some server implementations send title/body in the `data` payload
  /// instead of the `notification` payload.
  Future<void> _showFcmDataNotificationLocally(RemoteMessage message) async {
    final title = message.data['title'] ?? 'New Notification';
    final body = message.data['body'] ?? message.data['message'] ?? '';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'fcm_notifications',
      'Push Notifications',
      channelDescription: 'Notifications received via push when app is in foreground',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }

  void _setupRealtimeNotifications() {
    final user = SupabaseService.instance.getCurrentUser();
    if (user != null) {
      // Listen for new notifications for the current user
      _notificationSubscription = SupabaseService.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .listen(
            (notifications) {
              if (kDebugMode) {
                print(
                  '[NOTIFICATION] Received ${notifications.length} notifications for user ${user.id}',
                );
              }

              // Check if there are any unread notifications
              final unreadNotifications = notifications
                  .where((n) => n['is_read'] == false)
                  .toList();

              if (kDebugMode) {
                print(
                  '[NOTIFICATION] Found ${unreadNotifications.length} unread notifications',
                );
              }

              if (unreadNotifications.isNotEmpty) {
                // Sort by created_at descending to get the newest first
                unreadNotifications.sort((a, b) {
                  final aTime = a['created_at'] as String? ?? '';
                  final bTime = b['created_at'] as String? ?? '';
                  return bTime.compareTo(aTime);
                });

                // Show local push for any NEW unread notifications not yet shown
                for (final notification in unreadNotifications) {
                  final notifId = notification['id']?.toString() ?? '';
                  if (notifId.isNotEmpty && !_shownNotificationIds.contains(notifId)) {
                    _shownNotificationIds.add(notifId);
                    if (kDebugMode) {
                      print(
                        '[NOTIFICATION] Showing NEW notification: ${notification['title']} (id: $notifId)',
                      );
                    }
                    _showLocalNotification(notification);
                  }
                }
              }

              // Notify UI of changes immediately
              if (onNotificationsChanged != null) {
                if (kDebugMode) {
                  print(
                    '[NOTIFICATION] Notifying UI of notification changes - calling callback',
                  );
                }
                onNotificationsChanged!();
              }
            },
            onError: (error) {
              if (kDebugMode) {
                print('[NOTIFICATION] Stream error: $error');
              }
            },
          );
    } else {
      if (kDebugMode) {
        print('[NOTIFICATION] No user found, cannot setup notifications');
      }
    }
  }

  Future<void> _showLocalNotification(Map<String, dynamic> notification) async {
    // Determine notification channel based on type
    final notificationType = notification['type'] as String? ?? 'general';

    AndroidNotificationDetails androidDetails;

    // Admin-specific notifications with high priority
    if (notificationType == 'banking_details_added' ||
        notificationType == 'subaccount_approval_required' ||
        notificationType == 'partner_approved') {
      androidDetails = const AndroidNotificationDetails(
        'admin_alerts',
        'Admin Alerts',
        channelDescription:
            'Critical alerts for administrators requiring immediate attention',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
      );
    } else if (notificationType == 'deal_request') {
      // Trusted Partner deal request notifications with high priority
      androidDetails = const AndroidNotificationDetails(
        'deal_requests',
        'Deal Requests',
        channelDescription:
            'Notifications when members request deals from your business',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
      );
    } else if (notificationType == 'deal_approved' ||
        notificationType == 'pos_deal_approved' ||
        notificationType == 'deal_rejected') {
      // Member deal approval/rejection notifications with high priority
      androidDetails = const AndroidNotificationDetails(
        'deal_responses',
        'Deal Responses',
        channelDescription:
            'Notifications when businesses approve or reject your deal requests',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
      );
    } else if (notificationType == 'payment_received' ||
        notificationType == 'payment_success') {
      // Payment notifications with high priority
      androidDetails = const AndroidNotificationDetails(
        'payment_notifications',
        'Payment Notifications',
        channelDescription:
            'Notifications for successful payments and receipts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        channelShowBadge: true,
      );
    } else {
      // Default notification channel
      androidDetails = const AndroidNotificationDetails(
        'deal_notifications',
        'Deal Notifications',
        channelDescription: 'Notifications for deal authorizations and updates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
    }

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notification['id'].hashCode,
      title: notification['title'] ?? 'New Notification',
      body: notification['message'] ?? 'You have a new notification',
      notificationDetails: notificationDetails,
      payload: notification['id'].toString(),
    );
  }

  /// Show admin alert for banking details update
  Future<void> showAdminBankingAlert({
    required String title,
    required String message,
    required String notificationId,
  }) async {
    const AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'admin_alerts',
      'Admin Alerts',
      channelDescription:
          'Critical alerts for administrators requiring immediate attention',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId.hashCode,
      title: title,
      body: message,
      notificationDetails: notificationDetails,
      payload: notificationId,
    );
  }

  /// Show admin alert for Paystack subaccount approval
  Future<void> showAdminSubaccountApprovalAlert({
    required String title,
    required String message,
    required String notificationId,
  }) async {
    const AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'admin_alerts',
      'Admin Alerts',
      channelDescription:
          'Critical alerts for administrators requiring immediate attention',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId.hashCode,
      title: title,
      body: message,
      notificationDetails: notificationDetails,
      payload: notificationId,
    );
  }

  Future<void> showDealRequestNotification({
    required String title,
    required String message,
    required String notificationId,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'deal_requests',
          'Deal Requests',
          channelDescription:
              'Notifications when members request deals from your business',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId.hashCode,
      title: title,
      body: message,
      notificationDetails: notificationDetails,
      payload: notificationId,
    );
  }

  /// Show member notification for deal approval or rejection
  Future<void> showMemberDealResponseNotification({
    required String title,
    required String message,
    required String notificationId,
  }) async {
    const AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'deal_responses',
      'Deal Responses',
      channelDescription:
          'Notifications when businesses approve or reject your deal requests',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId.hashCode,
      title: title,
      body: message,
      notificationDetails: notificationDetails,
      payload: notificationId,
    );
  }

  /// Show payment notification (for member payment success and TP payment received)
  Future<void> showPaymentNotification({
    required String title,
    required String message,
    required String notificationId,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'payment_notifications',
          'Payment Notifications',
          channelDescription:
              'Notifications for successful payments and receipts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
          channelShowBadge: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId.hashCode,
      title: title,
      body: message,
      notificationDetails: notificationDetails,
      payload: notificationId,
    );
  }

  /// Request exemption from Android battery optimization (Doze mode).
  /// Without this, OEM-specific battery management (Samsung, Xiaomi, Huawei,
  /// Oppo, OnePlus, etc.) can kill the app's background process and prevent
  /// FCM from delivering push notifications.
  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      if (kIsWeb) return;
      if (!Platform.isAndroid) return;

      const platform = MethodChannel('com.locallekker.app/battery');
      final bool isIgnoring = await platform.invokeMethod('isIgnoringBatteryOptimizations');
      if (!isIgnoring) {
        _logger.i('FCM: Requesting battery optimization exemption');
        await platform.invokeMethod('requestIgnoreBatteryOptimizations');
      } else {
        _logger.d('FCM: Already exempt from battery optimization');
      }
    } catch (e) {
      // MethodChannel not available (e.g. older setup) - log but don't crash
      _logger.w('FCM: Could not check battery optimization: $e');
    }
  }

  /// Re-establish the Supabase Realtime subscription for the currently
  /// logged-in user. Call this immediately after a user signs in so that
  /// push notifications are active even though [initialize] was called
  /// before authentication completed.
  Future<void> reinitializeForCurrentUser() async {
    // Cancel any existing subscription first
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _shownNotificationIds.clear();
    _setupRealtimeNotifications();

    // Update FCM token for the newly signed-in user
    if (defaultTargetPlatform != TargetPlatform.windows) {
      await _updateFcmToken();
    }
  }

  void dispose() {
    _notificationSubscription?.cancel();
  }
}
