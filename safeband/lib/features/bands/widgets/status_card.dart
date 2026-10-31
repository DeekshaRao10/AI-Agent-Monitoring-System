import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class StatusCard extends StatelessWidget {
  final String wearerName;
  final int battery;
  final String lastSync;
  final bool online;

  const StatusCard({
    super.key,
    required this.wearerName,
    required this.battery,
    required this.lastSync,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Chip(
              avatar: Icon(
                Icons.circle,
                color: online ? Colors.green : Colors.grey,
                size: 10,
              ),
              label: Text(online ? "Band Online" : "Band Offline"),
            ),

            const SizedBox(height: 15),

            Text(
              "$wearerName is doing well",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.battery_full,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                Text("Battery $battery%"),
                const SizedBox(width: 20),
                Text("Last Sync $lastSync"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
