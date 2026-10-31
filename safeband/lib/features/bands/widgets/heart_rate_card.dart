import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class HeartRateCard extends StatelessWidget {
  final int heartRate;

  const HeartRateCard({
    super.key,
    required this.heartRate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.favorite,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Text(
                  "Heart Rate",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Center(
              child: Text(
                "$heartRate BPM",
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                heartRate >= 60 && heartRate <= 100
                    ? "Normal"
                    : "Abnormal",
                style: TextStyle(
                  color: heartRate >= 60 && heartRate <= 100
                      ? AppColors.primary
                      : AppColors.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 25),

            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),

                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      spots: [
                        FlSpot(0, heartRate.toDouble() - 4),
                        FlSpot(1, heartRate.toDouble() - 2),
                        FlSpot(2, heartRate.toDouble()),
                        FlSpot(3, heartRate.toDouble() + 2),
                        FlSpot(4, heartRate.toDouble() - 1),
                        FlSpot(5, heartRate.toDouble()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}