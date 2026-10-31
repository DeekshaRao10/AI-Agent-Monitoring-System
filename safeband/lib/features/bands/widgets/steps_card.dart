import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class StepsCard extends StatelessWidget {
  final int steps;
  final int goal;

  const StepsCard({
    super.key,
    required this.steps,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final double progress =
        (steps / goal).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [

            Row(
              children: [
                const Icon(
                  Icons.directions_walk,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  "Daily Steps",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            Center(
              child: Text(
                "$steps",
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                      fontWeight:
                          FontWeight.bold,
                    ),
              ),
            ),

            const SizedBox(height: 5),

            Center(
              child: Text(
                "Goal: $goal steps",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ),

            const SizedBox(height: 20),

            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius:
                  BorderRadius.circular(10),
              color: AppColors.primary,
              backgroundColor:
                  AppColors.divider,
            ),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: Text(
                "${(progress * 100).toStringAsFixed(0)}%",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}