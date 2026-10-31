import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/services/navigation_service.dart';
import 'features/auth/screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/background_alert_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
    // Firebase was already initialized natively via google-services.json — safe to ignore.
  }

  // Must be registered before runApp(), and must reference the same
  // top-level function every time — this is what lets FCM spin up a
  // background isolate and show the full-screen fall alert even if the
  // app is fully closed, not just backgrounded.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await NotificationService().initNotifications();

  // Free, client-side alternative to the (currently undeployed) Cloud
  // Function — keeps watching for a fall even after the app is closed,
  // without needing the Blaze plan. See background_alert_service.dart.
  await initBackgroundAlertService();

  runApp(const SafeBandApp());
}
class SafeBandApp extends StatelessWidget {
  const SafeBandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}