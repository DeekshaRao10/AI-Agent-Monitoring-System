import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class BandHeader extends StatelessWidget {
  final String wearerName;

  const BandHeader({
    super.key,
    required this.wearerName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),

        Expanded(
          child: Text(
            wearerName,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
          ),
        ),

        IconButton(
          onPressed: () {
            // TODO: Open Band Settings
          },
          icon: const Icon(
            Icons.settings_outlined,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}