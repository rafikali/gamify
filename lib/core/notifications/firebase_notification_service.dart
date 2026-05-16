import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';

const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'learnify_high_importance',
  'Learnify notifications',
  description: 'Important learning reminders and game updates.',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = DefaultFirebaseOptions.currentPlatform;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }

  debugPrint('Background notification received: ${message.messageId}');
}

class FirebaseNotificationService {
  FirebaseNotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging,
       _localNotifications = localNotifications;

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _localNotifications;
  StreamSubscription<String>? _tokenRefreshSub;
  FirebaseFirestore? _firestore;
  String? _activeUserId;
  final StreamController<RemoteMessage> _foregroundMessages =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationTaps =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<RemoteMessage> get foregroundMessages => _foregroundMessages.stream;
  Stream<Map<String, dynamic>> get notificationTaps => _notificationTaps.stream;

  static void registerBackgroundHandler() {
    if (_supportsMessagingOnCurrentPlatform) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  }

  Future<void> initialize() async {
    if (!_supportsMessagingOnCurrentPlatform) return;

    await _requestPermission();
    await _initializeLocalNotifications();
    await _configureForegroundPresentation();
    await _handleInitialMessage();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _notificationTaps.add(message.data);
    });
    _tokenRefreshSub = _firebaseMessaging.onTokenRefresh.listen((token) async {
      final firestore = _firestore;
      final userId = _activeUserId;
      if (firestore == null || userId == null) return;

      try {
        await _replaceStoredToken(
          firestore: firestore,
          userId: userId,
          token: token,
        );
      } catch (_) {
        // Token refresh should not interrupt the foreground app session.
      }
    });
  }

  Future<String?> getToken() {
    if (!_supportsMessagingOnCurrentPlatform) return Future.value();
    return _firebaseMessaging.getToken();
  }

  Future<void> syncTokenForUser({
    required FirebaseFirestore firestore,
    required String userId,
  }) async {
    if (!_supportsMessagingOnCurrentPlatform) return;

    _firestore = firestore;
    _activeUserId = userId;

    final token = await getToken();
    if (token == null || token.trim().isEmpty) return;

    await _replaceStoredToken(
      firestore: firestore,
      userId: userId,
      token: token,
    );
  }

  Future<void> clearTokenForUser({
    required FirebaseFirestore firestore,
    required String userId,
  }) async {
    if (!_supportsMessagingOnCurrentPlatform) return;

    await _deleteStoredTokens(firestore: firestore, userId: userId);
    _activeUserId = null;
    _firestore = null;
  }

  FirebaseMessaging get _firebaseMessaging {
    return _messaging ??= FirebaseMessaging.instance;
  }

  FlutterLocalNotificationsPlugin get _flutterLocalNotifications {
    return _localNotifications ??= FlutterLocalNotificationsPlugin();
  }

  Future<void> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');

    final androidPlugin = _flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _initializeLocalNotifications() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _flutterLocalNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          _notificationTaps.add(decoded);
        } else if (decoded is Map) {
          _notificationTaps.add(Map<String, dynamic>.from(decoded));
        }
      },
    );

    final androidPlugin = _flutterLocalNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  Future<void> _configureForegroundPresentation() {
    return _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _handleInitialMessage() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _notificationTaps.add(initialMessage.data);
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _foregroundMessages.add(message);

    final notification = message.notification;
    if (notification == null) return;

    await _flutterLocalNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _replaceStoredToken({
    required FirebaseFirestore firestore,
    required String userId,
    required String token,
  }) async {
    await _deleteStoredTokens(firestore: firestore, userId: userId);

    final profileRef = firestore.collection('profiles').doc(userId);
    final tokenRef = profileRef
        .collection('fcm_tokens')
        .doc(_tokenDocId(token));
    final tokenData = <String, dynamic>{
      'token': token,
      'platform': defaultTargetPlatform.name,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    await tokenRef.set(tokenData, SetOptions(merge: true));
    await profileRef.set(<String, dynamic>{
      'fcm_token': token,
      'fcm_platform': defaultTargetPlatform.name,
      'fcm_token_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _deleteStoredTokens({
    required FirebaseFirestore firestore,
    required String userId,
  }) async {
    final profileRef = firestore.collection('profiles').doc(userId);
    final existingTokens = await profileRef.collection('fcm_tokens').get();
    final batch = firestore.batch();

    for (final doc in existingTokens.docs) {
      batch.delete(doc.reference);
    }

    batch.set(profileRef, <String, dynamic>{
      'fcm_token': FieldValue.delete(),
      'fcm_platform': FieldValue.delete(),
      'fcm_token_updated_at': FieldValue.delete(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  String _tokenDocId(String token) {
    return base64Url.encode(utf8.encode(token));
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessages.close();
    _notificationTaps.close();
  }

  static bool get _supportsMessagingOnCurrentPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
