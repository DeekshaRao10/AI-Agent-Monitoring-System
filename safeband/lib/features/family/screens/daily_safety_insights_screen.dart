import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

const String rtdbUrl =
    'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app';

class DailySafetyInsightsScreen extends StatelessWidget {
  final String deviceId;
  final String wearerName;

  const DailySafetyInsightsScreen({
    super.key,
    required this.deviceId,
    required this.wearerName,
  });

  @override
  Widget build(BuildContext context) {
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: rtdbUrl,
    );

    final reference = database.ref('ai_insights/$deviceId');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: const Text(
          'Daily Safety Insights',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F7A7B),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: reference.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to load AI insights.'),
            );
          }

          final value = snapshot.data?.snapshot.value;

          if (value == null || value is! Map) {
            return const Center(
              child: Text(
                'No AI insights available yet.',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          final data = Map<String, dynamic>.from(value);

          final status =
              data['status']?.toString() ?? 'UNKNOWN';

          final message =
              data['message']?.toString() ?? 'No message available.';

          final action =
              data['recommendedAction']?.toString() ??
                  'Continue monitoring.';

          final routine = data['routineInsights'] is Map
              ? Map<String, dynamic>.from(data['routineInsights'])
              : <String, dynamic>{};

          final anomaly = data['anomalyDetection'] is Map
              ? Map<String, dynamic>.from(data['anomalyDetection'])
              : <String, dynamic>{};

          final steps = routine['latestSteps'] ?? 0;
          final days = routine['daysRecorded'] ?? 0;
          final average = routine['averageActivity'] ?? 0;

          Color statusColor;
          IconData statusIcon;
          String statusTitle;

          switch (status) {
            case 'NORMAL_ACTIVITY':
              statusColor = Colors.green;
              statusIcon = Icons.check_circle;
              statusTitle = 'Normal Activity';
              break;

            case 'UNUSUAL_ACTIVITY':
              statusColor = Colors.orange;
              statusIcon = Icons.warning_amber_rounded;
              statusTitle = 'Unusual Activity';
              break;

            case 'COLLECTING_BASELINE':
              statusColor = Colors.amber.shade800;
              statusIcon = Icons.insights;
              statusTitle = 'Learning Daily Routine';
              break;

            default:
              statusColor = Colors.blueGrey;
              statusIcon = Icons.info_outline;
              statusTitle = 'AI Status';
          }

          final timestamp = data['lastUpdated'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (data['lastUpdated'] as num).toInt() * 1000,
                )
              : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wearerName,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'AI-powered daily activity monitoring',
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 22),

                // AI STATUS CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: statusColor.withOpacity(0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        statusIcon,
                        color: statusColor,
                        size: 38,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        statusTitle,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ACTIVITY SUMMARY
                const Text(
                  'Activity Summary',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _infoCard(
                        Icons.directions_walk,
                        'Latest Steps',
                        '$steps',
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _infoCard(
                        Icons.calendar_today,
                        'Days Recorded',
                        '$days',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _infoCard(
                  Icons.analytics_outlined,
                  'Average Activity',
                  '$average',
                ),

                const SizedBox(height: 22),

                // RECOMMENDED ACTION
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Color(0xFF0F7A7B),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Recommended Action',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        action,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ANOMALY INFORMATION
                _infoCard(
                  Icons.monitor_heart_outlined,
                  'Anomaly Detection',
                  anomaly['status']?.toString() ?? 'Not available',
                ),

                const SizedBox(height: 20),

                if (timestamp != null)
                  Text(
                    'Last updated: ${timestamp.toLocal()}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),

                const SizedBox(height: 14),

                const Text(
                  'These AI insights are informational and do not '
                  'replace emergency alerts or medical assessment.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoCard(
    IconData icon,
    String title,
    String value,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF0F7A7B),
            size: 27,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
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