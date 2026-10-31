import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class AlertListener {
  StreamSubscription<DatabaseEvent>? _subscription;

  bool _ignoreFirstSnapshot = true;


  bool _lastFallState = false;

  void startListening({
    required String bandId,
    required Function(Map<String, dynamic>) onEmergency,
  }) {
    _subscription?.cancel();

    _ignoreFirstSnapshot = true;
    _lastFallState = false;

    print("==================================");
    print("Starting Realtime Database Listener");
    print("Listening on band: $bandId");
    print("==================================");

    final database = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL:
      'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app',
);

_subscription = database
    .ref("bands/$bandId")
    .onValue
    .listen((event) {
      final snapshot = event.snapshot;

      if (!snapshot.exists) {
        print("Band data not found.");
        return;
      }

      final data =
          Map<String, dynamic>.from(snapshot.value as Map);

      print("Realtime data: $data");

      if (_ignoreFirstSnapshot) {
        _ignoreFirstSnapshot = false;

       
        _lastFallState = data['fallDetected'] ?? false;

        print("Initial snapshot ignored.");
        return;
      }

      final bool fallDetected =
          data['fallDetected'] ?? false;

      if (fallDetected && !_lastFallState) {
        print(">>> OPENING EMERGENCY SCREEN <<<");

        onEmergency(data);
      }

      _lastFallState = fallDetected;
    });
  }

  void stopListening() {
    _subscription?.cancel();
  }
}
