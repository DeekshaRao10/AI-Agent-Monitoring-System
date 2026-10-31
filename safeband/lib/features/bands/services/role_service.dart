import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RoleService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>?> getCurrentMembership() async {
    final user = auth.currentUser;

    if (user == null) return null;

    final snapshot = await firestore
        .collection('bandMembers')
        .where('userId', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.data();
    }

    final userDoc =
        await firestore.collection('users').doc(user.uid).get();

    final familyId = userDoc.data()?['familyId']?.toString() ?? '';

    if (familyId.isEmpty) return null;

    return {
      'role': 'Member',
      'bandId': '',
      'familyId': familyId,
    };
  }
}


//RoleService identifies the role of the currently logged-in user. It first checks the bandMembers collection to see if the user is an Owner or Wearer. If no band membership is found, it checks the users collection for a family ID and treats the user as a family member. This role information is then used to control access to different features of the SafeBand application.