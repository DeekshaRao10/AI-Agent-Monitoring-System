import 'package:cloud_firestore/cloud_firestore.dart';
 

Future<String> resolveWearerUid({
  required String bandId,
  required String rawWearerUid,
}) async {
  if (rawWearerUid.isNotEmpty) return rawWearerUid;
 
  String resolved = '';
 
  try {
    final memberQuery = await FirebaseFirestore.instance
        .collection('bandMembers')
        .where('bandId', isEqualTo: bandId)
        .where('role', isEqualTo: 'WEARER')
        .limit(1)
        .get();
 
    if (memberQuery.docs.isNotEmpty) {
      resolved = memberQuery.docs.first.data()['userId'] ?? '';
    }
  } catch (_) {
   
  }
 
  if (bandId.isNotEmpty && resolved.isNotEmpty) {
    FirebaseFirestore.instance
        .collection('bands')
        .doc(bandId)
        .update({'wearerUid': resolved}).catchError((_) {});
  }
 
  return resolved;
}
 
