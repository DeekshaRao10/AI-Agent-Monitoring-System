import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

// Profile photos stored directly in Firestore as base64 text — no
// Firebase Storage, no Blaze plan needed. A resized profile photo
// (512x512, quality 80) is typically 30-150KB, well under Firestore's
// 1MB per-document limit even after base64's ~33% size inflation.
//
// Method names kept the same as before (savePhoto/getPhotoPath/
// clearPhoto) so every call site (Settings, PairSetupScreen, LocalAvatar)
// keeps working unchanged.
class LocalPhotoStore {
  static CollectionReference<Map<String, dynamic>> get _docs =>
      FirebaseFirestore.instance.collection('profilePhotos');

  static Future<String> savePhoto(String key, File source) async {
    final bytes = await source.readAsBytes();
    final base64Data = base64Encode(bytes);

    await _docs.doc(key).set({
      'data': base64Data,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return base64Data;
  }

  static Future<String?> getPhotoPath(String key) async {
    final doc = await _docs.doc(key).get();
    return doc.data()?['data'] as String?;
  }

  static Future<void> clearPhoto(String key) async {
    await _docs.doc(key).delete();
  }
}