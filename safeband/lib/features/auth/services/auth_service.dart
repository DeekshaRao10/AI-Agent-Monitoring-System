import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';//stores details
import 'package:firebase_messaging/firebase_messaging.dart';
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;
      Future<void> resetPassword(String email) async {
  await _auth.sendPasswordResetEmail(
    email: email,
  );
}

  Future<void> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    UserCredential userCredential =
        await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _firestore
        .collection('users')
        .doc(userCredential.user!.uid)
        .set({
      'name': name,
      'email': email,
      'phone': phone,
      'createdAt':
          FieldValue.serverTimestamp(),
    });
  }

  Future<void> login({
  required String email,
  required String password,
}) async {
  UserCredential userCredential =
      await _auth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );

  // Get the FCM token
  String? token =
      await FirebaseMessaging.instance.getToken();

  // Save it in Firestore
  await _firestore
      .collection('users')
      .doc(userCredential.user!.uid)
      .update({
    'fcmToken': token,
  });

  print("FCM Token saved!");
}
}