import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/local_photo_store.dart';
import '../theme/app_theme.dart';

class LocalAvatar extends StatelessWidget {
  final String photoKey;
  final double radius;
  final Color backgroundColor;
  final IconData fallbackIcon;
  final Color iconColor;

  const LocalAvatar({
    super.key,
    required this.photoKey,
    this.radius = 22,
    this.backgroundColor = AppColors.background,
    this.fallbackIcon = Icons.person,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: LocalPhotoStore.getPhotoPath(photoKey),
      builder: (context, snapshot) {
        final data = snapshot.data;
        Uint8List? bytes;

        if (data != null) {
          try {
            bytes = base64Decode(data);
          } catch (_) {
            bytes = null;
          }
        }

        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: bytes != null ? MemoryImage(bytes) : null,
          child: bytes == null
              ? Icon(fallbackIcon, color: iconColor, size: radius)
              : null,
        );
      },
    );
  }
}