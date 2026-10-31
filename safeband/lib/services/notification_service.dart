import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../core/services/navigation_service.dart';
import '../features/emergency/screens/emergency_screen.dart';
import '../firebase_options.dart';

// Vibrate 1s, pause 0.5s, four times over — noticeably longer/more
// insistent than Android's brief default notification buzz. This is a
// fixed-length pattern tied to the notification's own post/heads-up
// moment, separate from (and shorter than) the continuous vibration
// EmergencyScreen itself starts once actually opened — so a family
// member feels this the instant the alert arrives, on a locked/silenced
// phone, even before tapping anything.
final Int64List _fallAlertVibrationPattern =
    Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]);

// Channel id bumped again, 'fall_alerts_v2' -> 'fall_alerts_v3' — Android
// locks a channel's sound AND vibration pattern in at the moment it's
// first created on a device, and silently ignores any code change after
// that point. Any phone that already got v2 (sound fixed, but no custom
// vibration pattern) would never pick up vibration without a fresh id.
// Not const — Int64List (vibrationPattern) can't be a compile-time constant.
final AndroidNotificationChannel _fallAlertChannel = AndroidNotificationChannel(
  'fall_alerts_v3', // channel id
  'Fall Alerts', // channel name shown in phone settings
  description: 'Alerts sent when a SafeBand detects a fall',
  importance: Importance.max,
  // Same siren the Emergency Screen itself loops once opened — so the
  // heads-up/lock-screen notification sounds like this BEFORE it's even
  // tapped, not the plain default notification ping.
  sound: const RawResourceAndroidNotificationSound('emergency_siren'),
  playSound: true,
  enableVibration: true,
  vibrationPattern: _fallAlertVibrationPattern,
);

// Deliberately a separate asset from the launcher icon. Android renders
// the status-bar/notification icon as a flat white shape on most versions
// regardless of what you pass it — feeding it the full-color teal shield
// either gets masked into an unrecognizable blob or falls back to the
// stock Flutter logo. A dedicated white silhouette avoids both. Used by
// every plugin instance in this file — the app's own, the FCM background
// isolate's, and background_alert_service.dart's — so the icon is
// consistent no matter which of the three showed the alert.
const AndroidInitializationSettings _notificationAndroidInit =
    AndroidInitializationSettings('@drawable/ic_notification');

/// Runs in FCM's own background isolate whenever a data message arrives
/// while the app is backgrounded OR fully killed. This is the ONLY hook
/// that fires when the app isn't open, so it's what makes the emergency
/// alert show up without anyone having tapped anything.
///
/// Must stay a top-level function (not a class method) with exactly this
/// signature — that's an FCM requirement for background isolate entry
/// points — and needs @pragma('vm:entry-point') so release builds don't
/// tree-shake it away.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'FALL_DETECTED') return;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Already initialized — fine, this isolate just needs it available.
  }

  final localNotifications = await createInitializedFallAlertPlugin();
  await showFallAlertNotification(localNotifications, message.data);
}

/// Fresh isolate = fresh plugin instance; it has to be initialized before
/// use, since the main app's already-initialized instance isn't shared
/// across isolates. Shared by the FCM background handler above and by
/// background_alert_service.dart's own isolate — both need exactly this
/// same setup with nothing else attached (no tap-handling callback; that's
/// only meaningful in the main app's own instance, _initLocalNotifications
/// below).
Future<FlutterLocalNotificationsPlugin> createInitializedFallAlertPlugin() async {
  final plugin = FlutterLocalNotificationsPlugin();

  try {
    await plugin.initialize(
      const InitializationSettings(android: _notificationAndroidInit),
      // Safety net for the fully-killed case on OEM skins (Samsung/Oppo/
      // Vivo in particular) where the normal cold-start
      // getNotificationAppLaunchDetails() check can occasionally miss a tap
      // that came from a notification this isolate created rather than the
      // app's main instance. Must be a top-level/static callback — it can't
      // touch the navigator directly (no widget tree exists in this
      // isolate), so it doesn't need to do anything beyond exist; its
      // presence makes the plugin register the tap correctly so the next
      // full app launch's getNotificationAppLaunchDetails() picks it up.
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_fallAlertChannel);
  } catch (e) {
    // A bad/missing icon resource (or any other init failure) must never
    // take down the isolate that's supposed to be raising a fall alert —
    // this ran once as an *unhandled* exception inside main() before
    // runApp(), which left the whole app stuck on a blank screen. Log and
    // keep going; plugin.show() below may still no-op, but at least the
    // app itself boots.
    debugPrint("createInitializedFallAlertPlugin: init failed: $e");
  }

  return plugin;
}

@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  // Intentionally empty — see comment above. Real navigation happens via
  // getNotificationAppLaunchDetails() on the next cold start.
}

/// Builds and shows the actual alert — shared by the foreground FCM
/// listener, the FCM background isolate handler above, AND the fully
/// client-side background service (background_alert_service.dart), so it
/// looks and behaves identically no matter which of those three noticed
/// the fall. Takes a plain data map rather than a RemoteMessage since the
/// background service reads straight from Realtime Database and never
/// has an FCM message to unwrap in the first place.
Future<void> showFallAlertNotification(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final title = data['title'] ?? '🚨 Fall Detected!';
  final body = data['body'] ?? 'A SafeBand wearer may have fallen.';
  final deviceId = data['deviceId']?.toString() ?? '';

  _startNotificationVibration();

  await plugin.show(
    deviceId.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _fallAlertChannel.id,
        _fallAlertChannel.name,
        channelDescription: _fallAlertChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('emergency_siren'),
        enableVibration: true,
        vibrationPattern: _fallAlertVibrationPattern,
        // FLAG_INSISTENT (raw value 4, not otherwise exposed by this
        // plugin) — repeats BOTH the siren and the vibration pattern back
        // to back for as long as this notification stays posted, instead
        // of playing the pattern once and going quiet. Same flag a real
        // incoming-call notification uses. This is why cancelling the
        // notification the moment the alert clears (see
        // cancelFallAlertNotification below) isn't optional — without
        // it, this would just keep buzzing forever.
        additionalFlags: Int32List.fromList(<int>[4]),
        // The actual mechanism that draws over the lock screen / turns
        // the screen on without a tap — same trick alarm and incoming-call
        // apps use. Needs USE_FULL_SCREEN_INTENT in the manifest, and the
        // user also has to manually grant "Full screen notifications" for
        // the app once in system settings (Settings > Apps > SafeBand >
        // Notifications) — it can't be force-granted from code. Without
        // that toggle on, Android silently downgrades this to a normal
        // heads-up banner every time, which looks exactly like "the
        // notification came through but no emergency screen."
        //
        // Even with the toggle on: the guaranteed full-screen takeover
        // only happens when the device is locked/screen-off — that's an
        // OS policy (same class of privilege as incoming calls), not
        // something this app can override. If the screen is already on
        // and unlocked when the alert arrives, it will show as a heads-up
        // banner and rely on the user tapping it, which is handled below.
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      ),
    ),
    payload: deviceId,
  );
}

/// Stops the insistent siren+vibration loop started by
/// showFallAlertNotification above. Must be called with the SAME
/// deviceId once a fall alert actually clears — otherwise, because that
/// notification is FLAG_INSISTENT, Android just keeps repeating it
/// forever. Safe to call from any isolate/instance: Android's
/// notification system is keyed by (package, id) at the OS level, not
/// tied to whichever plugin instance originally posted it, so a fresh
/// throwaway plugin instance here reaches the same notification the
/// background service or the FCM isolate may have shown.
Future<void> cancelFallAlertNotification(String deviceId) async {
  try {
    await FlutterLocalNotificationsPlugin().cancel(deviceId.hashCode);
  } catch (e) {
    debugPrint("cancelFallAlertNotification: failed: $e");
  }
  _stopNotificationVibration();
}

// The channel's own vibrationPattern/FLAG_INSISTENT (above) is the
// "correct" Android way to do this, but proved unreliable on real
// hardware — confirmed working when EmergencyScreen drives it directly
// via this same vibration package with a Dart Timer, confirmed NOT
// vibrating on a Samsung phone when left to the native channel
// mechanism alone. Same fix applied here: drive it directly instead of
// trusting the OS to honor the channel's vibration config. Lives at this
// isolate/call's scope — for the real (background-service) path that's
// the long-running service isolate, so the Timer keeps firing exactly
// as long as this isolate does.
Timer? _notificationVibrationTimer;

void _startNotificationVibration() async {
  if (_notificationVibrationTimer != null) {
    print("_startNotificationVibration: already running, ignoring");
    return;
  }
  if (!await Vibration.hasVibrator()) {
    print("_startNotificationVibration: no vibrator on this device");
    return;
  }

  print("_startNotificationVibration: starting timer");

  Future<void> pulse() async {
    try {
      await Vibration.vibrate(duration: 1000);
    } catch (e) {
      print("_startNotificationVibration: pulse failed: $e");
    }
  }

  pulse();
  _notificationVibrationTimer =
      Timer.periodic(const Duration(milliseconds: 1500), (_) => pulse());
}

void _stopNotificationVibration() {
  print("_stopNotificationVibration: called, timer was "
      "${_notificationVibrationTimer != null ? 'running' : 'already null'}");
  _notificationVibrationTimer?.cancel();
  _notificationVibrationTimer = null;
  Vibration.cancel().then((_) {
    print("_stopNotificationVibration: Vibration.cancel() completed");
  }).catchError((e) {
    print("_stopNotificationVibration: Vibration.cancel() failed: $e");
  });
}

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission();

    print("Permission: ${settings.authorizationStatus}");

    String? token = await messaging.getToken();

    print("FCM Token:");
    print(token);

    await _saveTokenToFirestore(token);

    messaging.onTokenRefresh.listen(_saveTokenToFirestore);

    await _initLocalNotifications();

    // App is open and in the foreground — same shared alert builder as
    // the background handler, so it's consistent everywhere.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground FCM message received: ${message.messageId}");
      showFallAlertNotification(_localNotifications, message.data);
    });

    // App was backgrounded (not killed) and the user tapped the resulting
    // notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Notification tapped (app was backgrounded): ${message.messageId}");
      _handleMessageTap(message);
    });

    // Fallback cold-start path: covers the rare case where FCM's own
    // system notification (not ours) is what got tapped.
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      print("App launched from a terminated state via notification tap");
      _handleMessageTap(initialMessage);
    }

    // The path that matters for "app wasn't open at all": the OS itself
    // auto-launched the app because of our full-screen-intent notification
    // (or the user tapped the heads-up banner) — either way, this is how
    // we find out on a cold start and route straight to the emergency
    // screen instead of sitting on the splash/login flow.
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final bandId = launchDetails!.notificationResponse?.payload;
      if (bandId != null && bandId.isNotEmpty) {
        print("App launched via fall alert notification tap");
        _openEmergencyScreen(bandId);
      }
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    if (message.data['type'] != 'FALL_DETECTED') return;

    final bandId = message.data['deviceId'];
    if (bandId == null || bandId.isEmpty) return;

    _openEmergencyScreen(bandId);
  }

  void _openEmergencyScreen(String bandId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => EmergencyScreen(bandId: bandId, alertData: const {}),
        ),
      );
    });
  }

  Future<void> _initLocalNotifications() async {
    // Same reasoning as createInitializedFallAlertPlugin() above: this is
    // awaited from main() before runApp(), so an uncaught exception here
    // (e.g. a missing @drawable/ic_notification resource) blocks the app
    // from ever rendering — blank screen forever, no error shown on
    // screen. Notifications not working is recoverable; the app never
    // opening is not, so this must not be allowed to propagate.
    try {
      await _localNotifications.initialize(
        const InitializationSettings(android: _notificationAndroidInit),
        onDidReceiveNotificationResponse: (details) {
          final bandId = details.payload;
          if (bandId != null && bandId.isNotEmpty) {
            _openEmergencyScreen(bandId);
          }
        },
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_fallAlertChannel);
    } catch (e) {
      debugPrint("NotificationService: local notification init failed: $e");
    }
  }

  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return;

    final user = _auth.currentUser;

    if (user == null) {
      return;
    }

    await _firestore.collection('users').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );

    print("FCM token saved to Firestore for user ${user.uid}");
  }
}