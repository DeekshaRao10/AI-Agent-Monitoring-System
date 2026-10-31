import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/local_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/services/wearer_resolver.dart';
import '../../bands/screens/band_detail_screen.dart';
import '../../bands/screens/notifications_screen.dart';
import '../../pairing/screens/pair_scan_screen.dart';

class FamilyMembersScreen extends StatelessWidget {
  final String familyId;
  final String familyName;
  final String inviteCode;

  const FamilyMembersScreen({
    super.key,
    required this.familyId,
    required this.familyName,
    required this.inviteCode,
  });

  Future<void> _shareInviteCode(BuildContext context) async {
    await Share.share(
      'Join my family "$familyName" on SafeBand!\n\n'
      'Use invite code: $inviteCode\n\n'
      'Open the SafeBand app > Join Family > enter this code.',
      subject: 'SafeBand family invite',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const Icon(Icons.groups, color: AppColors.primary),
        title: const Text(
          "Family Management",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.black,
          ),
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('families')
                .doc(familyId)
                .collection('alerts')
                .where('resolved', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return IconButton(
                  icon: const Icon(Icons.error_outline, color: Colors.orange),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Notifications error: ${snapshot.error}"),
                      ),
                    );
                  },
                );
              }

              final unresolvedCount = snapshot.data?.docs.length ?? 0;
              final hasActiveAlert = unresolvedCount > 0;

              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      hasActiveAlert
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      color: hasActiveAlert
                          ? AppColors.danger
                          : AppColors.black,
                    ),
                    if (hasActiveAlert)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: AppColors.background,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unresolvedCount > 9 ? '9+' : '$unresolvedCount',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(familyId: familyId),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Members",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('families')
                  .doc(familyId)
                  .collection('members')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text("No family members found"),
                  );
                }

                final members = [...snapshot.data!.docs];

                members.sort((a, b) {
                  final aIsAdmin =
                      (a.data() as Map<String, dynamic>)['role'] == 'Admin';
                  final bIsAdmin =
                      (b.data() as Map<String, dynamic>)['role'] == 'Admin';

                  if (aIsAdmin == bIsAdmin) return 0;
                  return aIsAdmin ? -1 : 1;
                });

                return Column(
                  children: members.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    return _MemberCard(
                      familyId: familyId,
                      memberId: doc.id,
                      name: data['name'] ?? 'Unknown',
                      phone: data['phone'] ?? '',
                      role: data['role'] ?? 'Member',
                      notificationsEnabled:
                          data['notificationsEnabled'] ?? true,
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 24),

            const Text(
              "Bands",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bands')
                  .where('familyId', isEqualTo: familyId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text("No bands added yet"),
                  );
                }

                final bands = snapshot.data!.docs;

                return Column(
                  children: bands.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    final rawWearerUid = (data['wearerUid'] ?? '').toString();

                    return FutureBuilder<String>(
                      future: resolveWearerUid(
                        bandId: doc.id,
                        rawWearerUid: rawWearerUid,
                      ),
                      initialData: rawWearerUid,
                      builder: (context, wearerUidSnapshot) {
                        return _BandCard(
                          bandId: doc.id,
                          deviceId: data['deviceId'] ?? '',
                          bandName: data['bandName'] ?? 'SafeBand',
                          wearerName: data['wearerName'] ?? 'Unknown',
                          wearerUid: wearerUidSnapshot.data ?? '',
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 24),

            PrimaryButton(
              text: "Share Code",
              icon: Icons.share,
              onPressed: () => _shareInviteCode(context),
            ),

            const SizedBox(height: 12),

            PrimaryButton(
              text: "Add band",
              icon: Icons.add,
              outlined: true,
              foregroundColor: AppColors.primary,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PairScanScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final String familyId;
  final String memberId;
  final String name;
  final String phone;
  final String role;
  final bool notificationsEnabled;

  const _MemberCard({
    required this.familyId,
    required this.memberId,
    required this.name,
    required this.phone,
    required this.role,
    required this.notificationsEnabled,
  });

  Future<void> _setNotificationsEnabled(bool value) {
    return FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .collection('members')
        .doc(memberId)
        .update({'notificationsEnabled': value});
  }

  @override
  Widget build(BuildContext context) {
    final isWearer = role == 'Wearer';
    final isAdmin = role == 'Admin';

    final isMe = memberId == FirebaseAuth.instance.currentUser?.uid;
    final displayName = isMe ? "You" : name;

    final badgeText = role.toUpperCase();
    final badgeColor = isAdmin
        ? AppColors.success
        : (isWearer ? Colors.orange : AppColors.primary);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LocalAvatar(
                photoKey: memberId,
                backgroundColor: AppColors.primary,
                fallbackIcon: Icons.person,
                iconColor: AppColors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (isAdmin)
                      const Text(
                        "Admin",
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: const TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          if (!isWearer) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("App Notifications"),
                Switch(
                  value: notificationsEnabled,
                  activeColor: AppColors.primary,
                  onChanged: _setNotificationsEnabled,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BandCard extends StatelessWidget {
  final String bandId;
  final String deviceId;
  final String bandName;
  final String wearerName;
  final String wearerUid;

  const _BandCard({
    required this.bandId,
    required this.deviceId,
    required this.bandName,
    required this.wearerName,
    required this.wearerUid,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = wearerUid.isNotEmpty &&
        wearerUid == FirebaseAuth.instance.currentUser?.uid;
    final displayWearer = isMe ? "You" : wearerName;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BandDetailScreen(bandId: bandId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.background,
              child: Icon(Icons.watch, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bandName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Worn by $displayWearer",
                    style: const TextStyle(
                      color: AppColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _OnlineStatusChip(deviceId: deviceId),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}

class _OnlineStatusChip extends StatelessWidget {
  final String deviceId;

  const _OnlineStatusChip({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    if (deviceId.isEmpty) return const SizedBox.shrink();

    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref('bands/$deviceId/lastUpdated');

    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        bool online = false;

        final value = snapshot.data?.snapshot.value;

        if (value != null) {
          final lastUpdated = (value as num).toInt();
          final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

          online = (nowEpoch - lastUpdated) < 15;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: online ? AppColors.success : AppColors.grey,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            online ? "ONLINE" : "OFFLINE",
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}