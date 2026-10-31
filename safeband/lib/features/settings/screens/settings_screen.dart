import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/local_avatar.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/services/local_photo_store.dart';
import '../../pairing/screens/change_wifi_screen.dart';
import '../../auth/screens/login_screen.dart';


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Log out?"),
        content: const Text("You'll need to sign in again to see your bands."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openChangeWifi(BuildContext context, String familyId) async {
    final bandsSnap = await FirebaseFirestore.instance
        .collection('bands')
        .where('familyId', isEqualTo: familyId)
        .get();

    if (!context.mounted) return;

    if (bandsSnap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No bands added yet")),
      );
      return;
    }

    // Only one band -> skip straight to Change WiFi for it.....
    if (bandsSnap.docs.length == 1) {
      final band = bandsSnap.docs.first.data();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeWifiScreen(deviceId: band['deviceId'] ?? ''),
        ),
      );
      return;
    }

    // Multiple bands -> let the user pick which one.....
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    "Which band?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ...bandsSnap.docs.map((doc) {
                  final band = doc.data();

                  return ListTile(
                    leading: const Icon(Icons.watch, color: AppColors.primary),
                    title: Text(band['bandName'] ?? 'SafeBand'),
                    subtitle: Text("Worn by ${band['wearerName'] ?? ''}"),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChangeWifiScreen(
                            deviceId: band['deviceId'] ?? '',
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text("Settings"),
      ),
      body: user == null
          ? const Center(child: Text("Not signed in"))
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>?;
                final name = userData?['name'] ?? user.email ?? 'User';
                final familyId = userData?['familyId'] ?? '';

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Profile card — tap the avatar to pick/replace a
                    // profile photo.
                    _ProfileCard(
                      uid: user.uid,
                      name: name,
                      email: user.email,
                    ),

                    const SizedBox(height: 20),

                    _SettingsSectionLabel("Preferences"),

                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          if (familyId.isNotEmpty)
                            _NotificationToggleTile(
                              familyId: familyId,
                              uid: user.uid,
                            )
                          else
                            const _SettingsTile(
                              icon: Icons.notifications_none,
                              label: "Notification Preferences",
                              subtitle: "Join a family first",
                              onTap: null,
                            ),
                          const Divider(height: 1),
                          _SettingsTile(
                            icon: Icons.wifi,
                            label: "Change Band WiFi",
                            subtitle: familyId.isEmpty
                                ? "Join a family first"
                                : "Update a band's WiFi network",
                            onTap: familyId.isEmpty
                                ? null
                                : () => _openChangeWifi(context, familyId),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    _SettingsSectionLabel("About"),

                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const _SettingsTile(
                        icon: Icons.info_outline,
                        label: "App Version",
                        subtitle: "1.0.0",
                        onTap: null,
                      ),
                    ),

                    const SizedBox(height: 30),

                    PrimaryButton(
                      text: "Log Out",
                      backgroundColor: AppColors.danger,
                      icon: Icons.logout,
                      onPressed: () => _logout(context),
                    ),

                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
    );
  }
}


class _ProfileCard extends StatefulWidget {
  final String uid;
  final String name;
  final String? email;

  const _ProfileCard({
    required this.uid,
    required this.name,
    this.email,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  final ImagePicker _picker = ImagePicker();

  Key _avatarKey = UniqueKey();

  bool _saving = false;

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (picked == null) return;

    setState(() => _saving = true);

    try {
      await LocalPhotoStore.savePhoto(widget.uid, File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't upload photo: $e")),
        );
      }
    }

    if (!mounted) return;

    setState(() {
      _saving = false;
      _avatarKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _saving ? null : _pickPhoto,
            child: Stack(
              children: [
                LocalAvatar(
                  key: _avatarKey,
                  photoKey: widget.uid,
                  radius: 28,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Icon(Icons.edit,
                            size: 12, color: AppColors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.black,
                  ),
                ),
                if ((widget.email ?? '').isNotEmpty)
                  Text(
                    widget.email!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.mutedText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _NotificationToggleTile extends StatelessWidget {
  final String familyId;
  final String uid;

  const _NotificationToggleTile({required this.familyId, required this.uid});

  @override
  Widget build(BuildContext context) {
    final memberRef = FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .collection('members')
        .doc(uid);

    return StreamBuilder<DocumentSnapshot>(
      stream: memberRef.snapshots(),
      builder: (context, snapshot) {
        final enabled =
            (snapshot.data?.data() as Map<String, dynamic>?)?['notificationsEnabled'] ??
                true;

        return ListTile(
          leading: const Icon(Icons.notifications_none, color: AppColors.primary),
          title: const Text("Notification Preferences",
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text(
            "Get notified when a fall is detected",
            style: TextStyle(fontSize: 12),
          ),
          trailing: Switch(
            value: enabled,
            activeColor: AppColors.primary,
            onChanged: (value) {
              memberRef.update({'notificationsEnabled': value});
            },
          ),
        );
      },
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String title;

  const _SettingsSectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.mutedText,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppColors.mutedText)
          : null,
      onTap: onTap,
    );
  }
}