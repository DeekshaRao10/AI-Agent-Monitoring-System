import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import 'notification_service.dart';

const String _rtdbUrl =
    'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app';

/// Free, no-server alternative to the Cloud Function + FCM path already
/// built in notification_service.dart / functions/index.js. Runs the same
/// "watch for a fall, show the full-screen alert" behavior, but entirely
/// on this phone via a persistent Android foreground service, instead of
/// a server pushing to it — so it works without the Blaze plan the Cloud
/// Function needs to deploy at all.
///
/// Tradeoff (deliberately chosen over the Cloud Function path — see the
/// conversation this was built from): this is less reliable than a real
/// FCM push against aggressive OEM battery management or the user force-
/// stopping the app, both of which can kill this service in ways FCM's
/// OS-level wake can sometimes survive. The Cloud Function code is left
/// in place, undeployed, in case that tradeoff ever gets revisited.
Future<void> initBackgroundAlertService() async {
  // Without this exemption, several OEM battery managers (confirmed on
  // both Vivo and Samsung, almost certainly others) kill this service's
  // isolate shortly after the screen locks — the fall-watch RTDB listener
  // just silently stops running, with no crash, no error, nothing. This
  // shows Android's own "Allow SafeBand to run in the background?" system
  // dialog once; if the user denies it, the service still starts, just
  // with the same reliability caveat as before.
  try {
    await Permission.ignoreBatteryOptimizations.request();
  } catch (_) {
    // Not fatal — the service below still starts either way.
  }

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      // No notificationChannelId here on purpose: leaving it unset makes
      // the plugin create and use its own built-in "FOREGROUND_DEFAULT"
      // channel internally, inside the actual Service's onCreate() — the
      // one code path in BackgroundService.java that's guaranteed to run
      // at the right time. A custom channel id here means the plugin
      // trusts the app to have created it first, and that pre-creation
      // (tried and reverted) still crashed with the same "Bad
      // notification for startForeground", so this sidesteps it.
      initialNotificationTitle: 'SafeBand',
      initialNotificationContent: 'Watching for fall alerts',
      foregroundServiceNotificationId: 999,
      // Correct category for "keeps a connection open, watching for
      // remote data changes" — this is an RTDB listener, not audio,
      // location, media playback, etc.
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    // Required by configure() even though this service only targets
    // Android for now — flutter_background_service has no true
    // background-isolate equivalent on iOS (backgroundRefresh is the
    // closest, and far less reliable there than Android's foreground
    // service), so this is left at its defaults rather than built out.
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();
}

/// Runs in its own isolate, independent of the app's UI — this is what
/// keeps working after the app is closed. Needs @pragma('vm:entry-point')
/// for the same reason firebaseMessagingBackgroundHandler does: release
/// builds would otherwise tree-shake it away since nothing in the visible
/// call graph appears to reference it directly.
@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Already initialized — fine, this isolate just needs it available.
  }

  final localNotifications = await createInitializedFallAlertPlugin();

  StreamSubscription<DatabaseEvent>? subscription;
  bool ignoreFirstSnapshot = true;
  bool lastFallState = false;

  Future<void> watchBand(String bandId, String bandName) async {
    await subscription?.cancel();
    ignoreFirstSnapshot = true;
    lastFallState = false;

    print("BackgroundAlertService: watching band $bandId");

    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _rtdbUrl,
    ).ref('bands/$bandId');

    subscription = ref.onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is! Map) return;

      final data = Map<String, dynamic>.from(value);
      final fallDetected = data['fallDetected'] == true;

      print("BackgroundAlertService: data=$data");

      // Same "ignore whatever the band already was on connect, only act
      // on a false->true transition" logic as AlertListener — otherwise
      // an emergency already in progress when this service (re)starts
      // would immediately re-fire a notification for it.
      if (ignoreFirstSnapshot) {
        ignoreFirstSnapshot = false;
        lastFallState = fallDetected;
        print("BackgroundAlertService: initial snapshot ignored");
        return;
      }

      if (fallDetected && !lastFallState) {
        print("BackgroundAlertService: fall transition detected, showing notification");
        showFallAlertNotification(localNotifications, {
          'title': '🚨 Fall Detected!',
          'body': '$bandName wearer may have fallen. Tap to check on them.',
          'deviceId': bandId,
        });
      } else if (!fallDetected && lastFallState) {
        // The notification is FLAG_INSISTENT (keeps repeating siren +
        // vibration on its own — see showFallAlertNotification), so it
        // has to be explicitly cancelled once the alert clears. Without
        // this, a phone that never actually opened the Emergency Screen
        // (never tapped the notification) would keep buzzing forever
        // even after the wearer hit "I'm OK" elsewhere.
        print("BackgroundAlertService: fall cleared, cancelling notification");
        cancelFallAlertNotification(bandId);
      }

      lastFallState = fallDetected;
    }, onError: (e) {
      print("BackgroundAlertService: listener error: $e");
    });
  }

  // Same familyId -> first band lookup dashboard_screen.dart already uses
  // for its own (foreground-only) AlertListener — kept consistent with
  // that rather than introducing a different resolution rule here.
  Future<void> resolveAndWatchBand() async {
    // FirebaseAuth.instance.currentUser can still read null for a moment
    // right after Firebase.initializeApp() in a *fresh* isolate — auth
    // state restoration from disk happens asynchronously, so a synchronous
    // read here races it. Waiting for the first authStateChanges() event
    // instead gives it a chance to finish rehydrating before giving up;
    // without this, a fresh service start could silently never attach a
    // listener at all if this isolate happened to check before that
    // finished, which looks identical from the outside to "nothing
    // detected the fall."
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null, orElse: () => null)
            .timeout(const Duration(seconds: 10), onTimeout: () => null);

    if (user == null) {
      print("BackgroundAlertService: no signed-in user, not watching any band");
      return;
    }

    final firestore = FirebaseFirestore.instance;

    final userDoc = await firestore.collection('users').doc(user.uid).get();
    final familyId = userDoc.data()?['familyId']?.toString() ?? '';
    if (familyId.isEmpty) {
      print("BackgroundAlertService: user ${user.uid} has no familyId");
      return;
    }

    final bandsSnap = await firestore
        .collection('bands')
        .where('familyId', isEqualTo: familyId)
        .limit(1)
        .get();

    if (bandsSnap.docs.isEmpty) {
      print("BackgroundAlertService: no band found for familyId $familyId");
      return;
    }

    final band = bandsSnap.docs.first.data();
    final deviceId = band['deviceId']?.toString() ?? '';
    final bandName = band['bandName']?.toString() ?? 'SafeBand';
    if (deviceId.isEmpty) return;

    await watchBand(deviceId, bandName);
  }

  await resolveAndWatchBand();

  // Re-check periodically in case the signed-in user joins/changes bands
  // while this service is already running — cheap (one Firestore read),
  // and otherwise the service would never notice without a restart.
  Timer.periodic(const Duration(minutes: 5), (_) => resolveAndWatchBand());
}
