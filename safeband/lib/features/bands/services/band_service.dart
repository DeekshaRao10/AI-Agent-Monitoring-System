import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../firebase_options.dart';

class BandService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  Future<void> createWearer({
    required String name,
    required int age,
    required String email,
    required String address,
  }) async {
    final user = auth.currentUser!;

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('wearers')
        .add({
      'name': name,
      'age': age,
      'email': email,
      'address': address,
      'photoUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createBand({
    required String deviceId,
    required String bandName,
    required String wearerName,
    required int age,
    required String address,
    required String bloodGroup,
    required String medicalConditions,
    required String doctorPhone,
    String? wearerEmail,
    String? wearerPassword,
  }) async {
    print("BandService: createBand() started");

    final user = auth.currentUser!;

    // Get owner's familyId
    final userDoc =
        await firestore.collection('users').doc(user.uid).get();

    final familyId = userDoc.data()?['familyId'];

    // Check if band already exists
    final existingBand = await firestore
        .collection('bands')
        .where('deviceId', isEqualTo: deviceId)
        .limit(1)
        .get();

    if (existingBand.docs.isNotEmpty) {
      throw Exception("This band is already registered.");
    }
    final bandRef = await firestore.collection('bands').add({
      'deviceId': deviceId,
      'ownerId': user.uid,
      'familyId': familyId,
      'bandName': bandName,
      'wearerName': wearerName,
      'wearerUid': user.uid,
      'age': age,
      'address': address,
      'bloodGroup': bloodGroup,
      'medicalConditions': medicalConditions,
      'doctorPhone': doctorPhone,
      'heartRate': 0,
      'steps': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Add OWNER
    await firestore.collection('bandMembers').add({
      'bandId': bandRef.id,
      'userId': user.uid,
      'role': 'OWNER',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create WEARER account (optional)
    if (wearerEmail != null &&
        wearerPassword != null &&
        wearerEmail.isNotEmpty &&
        wearerPassword.isNotEmpty) {
      FirebaseApp secondaryApp;

      try {
        try {
          secondaryApp = Firebase.app('WearerApp');
        } catch (_) {
          secondaryApp = await Firebase.initializeApp(
            name: 'WearerApp',
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }

        print("==================================");
print("Creating wearer Firebase account");
print("Email: $wearerEmail");
print("Password length: ${wearerPassword.length}");

final secondaryAuth =
    FirebaseAuth.instanceFor(app: secondaryApp);

print("Calling createUserWithEmailAndPassword()...");

final wearerCredential =
    await secondaryAuth.createUserWithEmailAndPassword(
  email: wearerEmail,
  password: wearerPassword,
);

print("Firebase Auth account created!");
print("Wearer UID = ${wearerCredential.user!.uid}");

final wearerUid = wearerCredential.user!.uid;

      
        await bandRef.update({'wearerUid': wearerUid});

        // Create wearer user document
        await firestore.collection('users').doc(wearerUid).set({
          'name': wearerName,
          'email': wearerEmail,
          'familyId': familyId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Add wearer to band
        await firestore.collection('bandMembers').add({
          'bandId': bandRef.id,
          'userId': wearerUid,
          'role': 'WEARER',
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (familyId != null &&
            familyId.toString().isNotEmpty) {
          await firestore
              .collection('families')
              .doc(familyId)
              .collection('members')
              .doc(wearerUid)
              .set({
            'uid': wearerUid,
            'name': wearerName,
            'email': wearerEmail,
            'role': 'Wearer',
            'familyId': familyId,
            'joinedAt': FieldValue.serverTimestamp(),
          });
        }

        await secondaryAuth.signOut();

        return wearerUid;
      } on FirebaseAuthException catch (e) {
  print("==================================");
  print("FirebaseAuthException");
  print("Code: ${e.code}");
  print("Message: ${e.message}");
  print("==================================");

  await bandRef.delete();
  rethrow;
} catch (e, st) {
  print("==================================");
  print("Unknown Exception");
  print(e);
  print(st);
  print("==================================");

  await bandRef.delete();
  rethrow;
}
        }

  
    return user.uid;
  }
}


//User Registers Band
        
//Get Logged-in User
        
//Get Family ID
        
//Check Duplicate Band
       
//Create Band Document
//Add OWNER
        
//Create Wearer Firebase Account
//Update Band with Wearer UID
//Create Wearer User Document
//Add WEARER to bandMembers
//Add WEARER to Family
//Return Wearer UID