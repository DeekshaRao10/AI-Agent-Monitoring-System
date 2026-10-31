import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback?
      onPressed; // Stores the function that runs when the button is clicked.
      // Nullable so callers can disable the button (e.g. while a request
      // is in flight) — ElevatedButton/OutlinedButton already grey
      // themselves out automatically when onPressed is null.

  // Optional overrides. When left unset, the button renders exactly as it
  // always has (solid AppColors.primary background) — every existing call
  // site elsewhere in the app is unaffected. These exist so other screens
  // (like the Fall Alert screen) can reuse this same widget instead of
  // duplicating button styling code.
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconData? icon;
  final bool outlined;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedForeground = foregroundColor ?? AppColors.white;
    final resolvedBackground = backgroundColor ?? AppColors.primary;

    final child = icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(text),
            ],
          )
        : Text(text);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: resolvedForeground,
                side: BorderSide(color: resolvedForeground),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: child,
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: resolvedBackground,
                foregroundColor: resolvedForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: child,
            ),
    );
  }
}
