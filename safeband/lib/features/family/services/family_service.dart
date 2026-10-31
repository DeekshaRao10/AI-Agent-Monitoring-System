//Performs operations on Firebase create, read, update family and members.....

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamilyService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // Generate 6-digit invite code
  String generateInviteCode() {
    final random = Random();

    return (100000 +
            random.nextInt(900000))
        .toString();
  }

  // CREATE FAMILY
  Future<Map<String, String>>
      createFamily(
    String familyName,
  ) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception(
        "User not logged in",
      );
    }

    final inviteCode =
        generateInviteCode();

    final doc =
        _firestore.collection(
          'families',
        ).doc();

    await doc.set({
      'familyId': doc.id,
      'familyName': familyName,
      'inviteCode': inviteCode,
      'createdBy': user.uid,
      'createdAt':
          FieldValue.serverTimestamp(),
    });

    // Save familyId in user document
    await _firestore
        .collection('users')
        .doc(user.uid)
        .update({
      'familyId': doc.id,
    });

    // Add creator as first member
    final userDoc = await _firestore
    .collection('users')
    .doc(user.uid)
    .get();

await _firestore
    .collection('families')
    .doc(doc.id)
    .collection('members')
    .doc(user.uid)
    .set({
  'uid': user.uid,
  'name': userDoc.data()?['name'] ?? '',
  'email': userDoc.data()?['email'] ?? '',
  // Was never being saved before, even though users/{uid} already has it
  // from signup — FamilyMembersScreen needs this to show real phone
  // numbers instead of leaving them blank.
  'phone': userDoc.data()?['phone'] ?? '',
  'role': 'Admin',
'familyId': doc.id,
  // Default on; this is what the "App Notifications" toggle in
  // FamilyMembersScreen actually reads/writes, and what the alert
  // listener checks before sending a push to this member.
  'notificationsEnabled': true,
  'joinedAt':
      FieldValue.serverTimestamp(),
});

    return {
      'familyId': doc.id,
      'inviteCode': inviteCode,
    };
  }

  // FIND FAMILY BY INVITE CODE
  Future<Map<String, dynamic>?>
      getFamilyByCode(
    String inviteCode,
  ) async {
    final result =
        await _firestore
            .collection('families')
            .where(
              'inviteCode',
              isEqualTo: inviteCode,
            )
            .get();

    if (result.docs.isEmpty) {
      return null;
    }

    return result.docs.first.data();
  }

  // JOIN FAMILY USING INVITE CODE
  Future<void> joinFamily(
  String inviteCode,
) async {
  final user = _auth.currentUser;

  if (user == null) {
    throw Exception(
      "User not logged in",
    );
  }

  final familyQuery =
      await _firestore
          .collection('families')
          .where(
            'inviteCode',
            isEqualTo: inviteCode,
          )
          .get();

  if (familyQuery.docs.isEmpty) {
    throw Exception(
      "Invalid Invite Code",
    );
  }

  final familyDoc =
      familyQuery.docs.first;

  final familyId =
      familyDoc.id;

  final userDoc =
      await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

  await _firestore
      .collection('families')
      .doc(familyId)
      .collection('members')
      .doc(user.uid)
      .set({
    'uid': user.uid,
    'name':
        userDoc.data()?['name'] ?? '',
    'email':
        userDoc.data()?['email'] ?? '',
    'phone':
        userDoc.data()?['phone'] ?? '',
    'role': 'Member',
    'familyId': familyId,
    'notificationsEnabled': true,
    'joinedAt':
        FieldValue.serverTimestamp(),
  });

  await _firestore
      .collection('users')
      .doc(user.uid)
      .update({
    'familyId': familyId,
  });
}
}