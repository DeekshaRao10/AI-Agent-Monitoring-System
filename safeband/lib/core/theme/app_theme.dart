import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF006D6F);

  static const background = Color(0xFFE3F1F4);

  static const white = Colors.white;
  static const textOnColor = Colors.white;

  static const black = Colors.black;
  static const grey = Colors.grey;

  static const success = Colors.green;
  static const danger = Colors.red;
  static const divider = Color(0xFFE0E0E0);

  static const mutedText = Colors.black54;


  static const alertCard = Color(0xFFE53935);
  static const alertButton = Color(0xFFB71C1C);
  static const alertOverlay = Colors.white24;
  static const alertMutedText = Colors.white70;
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
    ),

    scaffoldBackgroundColor: AppColors.background,

    cardTheme: const CardThemeData(
      color: AppColors.white,
      elevation: 2,
      margin: EdgeInsets.zero,
    ),
  );
}
