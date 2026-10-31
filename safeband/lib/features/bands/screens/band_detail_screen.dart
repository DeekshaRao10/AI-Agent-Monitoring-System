import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/wearer_resolver.dart';

import '../widgets/medical_card.dart';
import '../../pairing/screens/change_wifi_screen.dart';

// NOTE: this rebuild matches the new "Band Detail" reference design and
// bakes the header/status/heart-rate/blood-oxygen/steps/last-movement
// cards directly into this file instead of the old separate
// band_header.dart / status_card.dart / heart_rate_card.dart /
// steps_card.dart widgets — those are no longer used here, only
// medical_card.dart still is (for the blood group / conditions / doctor
// section further down the scroll, not shown in the reference crop).

const String _rtdbUrl =
    'https://safeband-a3b89-default-rtdb.asia-southeast1.firebasedatabase.app';

class BandDetailScreen extends StatelessWidget {
  final String bandId;

  const BandDetailScreen({
    super.key,
    required this.bandId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bands')
            .doc(bandId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData ||
              !snapshot.data!.exists ||
              snapshot.data!.data() == null) {
            return const Center(child: Text("Band not found"));
          }

          final band = snapshot.data!.data() as Map<String, dynamic>;
          final deviceId = band['deviceId'] ?? '';
          final wearerName = band['wearerName'] ?? '';

          final rawWearerUid = (band['wearerUid'] ?? '').toString();

          final stepGoal = band['stepGoal'] ?? 5000;

          // Same self-healing lookup as Dashboard/Family Management —
          // bands created before wearerUid existed (or with a separate
          // wearer account never linked back) still resolve to the real
          // wearer via wearer_resolver.dart. No ownerId fallback: that
          // made "You" show for the admin on every band they own,
          // instead of only the one they actually wear.
          return FutureBuilder<String>(
            future: resolveWearerUid(
              bandId: bandId,
              rawWearerUid: rawWearerUid,
            ),
            initialData: rawWearerUid,
            builder: (context, wearerUidSnapshot) {
              final wearerUid = wearerUidSnapshot.data ?? '';

              // Whenever the signed-in account IS the wearer this band
              // belongs to, show "You" instead of their stored name —
              // here, in the top bar, and in the status line below.
              final isMe = wearerUid.isNotEmpty &&
                  wearerUid == FirebaseAuth.instance.currentUser?.uid;
              final displayName = isMe ? "You" : wearerName;

              return SafeArea(
                child: Column(
                  children: [
                    _DetailAppBar(
                      wearerName: displayName,
                      onSettingsTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChangeWifiScreen(deviceId: deviceId),
                          ),
                        );
                      },
                    ),

                    Expanded(
                      child: _LiveVitals(
                        deviceId: deviceId,
                        builder: (context, online, lastSyncText, heartRate,
                            spo2, liveSteps) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _StatusCard(
                                  wearerName: displayName,
                                  isMe: isMe,
                                  online: online,
                                  battery: band['battery'] ?? 100,
                                  lastSyncText: lastSyncText,
                                  // Only offered when nobody's explicitly
                                  // linked as this band's wearer yet — a
                                  // deliberate one-tap action, not an
                                  // automatic guess, so it can't cause
                                  // the "You shows for everyone" bug
                                  // again. Once tapped, this band always
                                  // shows "You" for this account from
                                  // then on.
                                  showClaimButton: wearerUid.isEmpty,
                                  onClaim: () {
                                    final uid = FirebaseAuth
                                        .instance.currentUser?.uid;
                                    if (uid == null) return;

                                    FirebaseFirestore.instance
                                        .collection('bands')
                                        .doc(bandId)
                                        .update({'wearerUid': uid});
                                  },
                                ),

                                const SizedBox(height: 16),

                                _HeartRateCard(heartRate: heartRate),

                                const SizedBox(height: 16),

                                _BloodOxygenCard(
                                  spo2: spo2,
                                  heartRate: heartRate,
                                ),

                                const SizedBox(height: 16),

                                _StepsCard(
                                  bandId: bandId,
                                  // Live RTDB step count takes priority
                                  // over the static (never actually
                                  // written) Firestore field.
                                  steps: liveSteps > 0
                                      ? liveSteps
                                      : (band['steps'] ?? 0),
                                  goal: stepGoal,
                                ),

                                const SizedBox(height: 16),

                                _LastMovementCard(lastSyncText: lastSyncText),

                                const SizedBox(height: 16),

                                MedicalCard(
                                  bloodGroup: band['bloodGroup'] ?? '',
                                  medicalConditions:
                                      band['medicalConditions'] ?? '',
                                  doctorPhone: band['doctorPhone'] ?? '',
                                  address: band['address'] ?? '',
                                ),

                                const SizedBox(height: 16),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Top bar: back arrow, small badge + wearer name, gear icon (-> Change
/// WiFi). No dropdown/wearer-switcher yet — there's no multi-profile
/// data model behind that in the reference design, so it's left out
/// rather than faked.
class _DetailAppBar extends StatelessWidget {
  final String wearerName;
  final VoidCallback onSettingsTap;

  const _DetailAppBar({
    required this.wearerName,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.black),
            onPressed: () => Navigator.pop(context),
          ),
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.watch, color: AppColors.textOnColor, size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            wearerName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.black,
            ),
          ),
          const Spacer(),
          IconButton(
            // WiFi icon instead of a generic gear — this button only
            // ever opens Change WiFi.
            icon: const Icon(Icons.wifi, color: AppColors.black),
            onPressed: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

/// Reads the live RTDB node once and hands online/lastSync/heartRate/spo2
/// down to [builder] — heartRate and spo2 come from here (real, ESP32-
/// reported data) instead of the old Firestore heartRate:0 placeholder
/// that never actually updated.
class _LiveVitals extends StatelessWidget {
  final String deviceId;
  final Widget Function(
    BuildContext context,
    bool online,
    String lastSyncText,
    int heartRate,
    int spo2,
    int steps,
  ) builder;

  const _LiveVitals({required this.deviceId, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (deviceId.isEmpty) {
      return builder(context, false, 'Unknown', 0, 0, 0);
    }

    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _rtdbUrl,
    ).ref('bands/$deviceId');

    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        bool online = false;
        String lastSyncText = 'Unknown';
        int heartRate = 0;
        int spo2 = 0;
        // Real step count from the band's MPU6050 pedometer, reported
        // alongside heartRate/spo2 every 5s — same live source, not the
        // static Firestore 'steps' field that nothing ever wrote to.
        int steps = 0;

        final value = snapshot.data?.snapshot.value;

        if (value is Map) {
          final data = Map<String, dynamic>.from(value);

          heartRate = (data['heartRate'] as num?)?.toInt() ?? 0;
          spo2 = (data['spo2'] as num?)?.toInt() ?? 0;
          steps = (data['steps'] as num?)?.toInt() ?? 0;

          final lastUpdated = (data['lastUpdated'] as num?)?.toInt();

          if (lastUpdated != null) {
            final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final diff = nowEpoch - lastUpdated;

            // Same 15s freshness window used everywhere else in the app.
            online = diff < 15;

            if (diff < 60) {
              lastSyncText = diff <= 2 ? 'Just now' : '${diff}s ago';
            } else if (diff < 3600) {
              lastSyncText = '${diff ~/ 60}m ago';
            } else {
              lastSyncText = '${diff ~/ 3600}h ago';
            }
          }
        }

        return builder(context, online, lastSyncText, heartRate, spo2, steps);
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String wearerName;
  final bool isMe;
  final bool online;
  final int battery;
  final String lastSyncText;
  final bool showClaimButton;
  final VoidCallback? onClaim;

  const _StatusCard({
    required this.wearerName,
    this.isMe = false,
    required this.online,
    required this.battery,
    required this.lastSyncText,
    this.showClaimButton = false,
    this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: online ? AppColors.success : AppColors.grey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: AppColors.textOnColor),
                const SizedBox(width: 6),
                Text(
                  online ? "Band Online" : "Band Offline",
                  style: const TextStyle(
                    color: AppColors.textOnColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isMe ? "You're doing well" : "$wearerName is doing well",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.battery_std, size: 16, color: AppColors.mutedText),
              const SizedBox(width: 4),
              Text(
                "$battery% Battery",
                style: const TextStyle(color: AppColors.mutedText, fontSize: 13),
              ),
              const Text(" • ", style: TextStyle(color: AppColors.mutedText)),
              Text(
                "Last synced $lastSyncText",
                style: const TextStyle(color: AppColors.mutedText, fontSize: 13),
              ),
            ],
          ),

          // Only shown when nobody's explicitly linked as this band's
          // wearer yet (e.g. an older band from before wearerUid
          // existed). Tapping this is a deliberate, one-time claim —
          // not an automatic guess — so it can't cause "You"/the
          // profile photo to wrongly show up on every band again.
          if (showClaimButton) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onClaim,
              child: const Text(
                "This is my band — set me as the wearer",
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeartRateCard extends StatefulWidget {
  final int heartRate;

  const _HeartRateCard({required this.heartRate});

  @override
  State<_HeartRateCard> createState() => _HeartRateCardState();
}

class _HeartRateCardState extends State<_HeartRateCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationForBpm(widget.heartRate),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _HeartRateCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // As the live heart rate changes, the wave's speed changes with it —
    // higher BPM visibly scrolls/pulses faster, lower BPM slows down.
    if (oldWidget.heartRate != widget.heartRate) {
      _controller.duration = _durationForBpm(widget.heartRate);
    }
  }

  Duration _durationForBpm(int bpm) {
    final safeBpm = bpm > 0 ? bpm : 75;
    final ms = (90000 / safeBpm).round().clamp(600, 3000);
    return Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heartRate = widget.heartRate;

    // Simple resting-range read: not a medical diagnosis, just a rough
    // label matching the reference design's "Resting Normal" pill.
    final isNormal = heartRate == 0 || (heartRate >= 60 && heartRate <= 100);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: AppColors.danger, size: 18),
              const SizedBox(width: 6),
              const Text(
                "HEART RATE",
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                "$heartRate",
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "bpm",
                  style: TextStyle(color: AppColors.mutedText, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRect(
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _WavePainter(
                      color: const Color(0xFF1B5E20), // dark green trace
                      heartRate: heartRate,
                      phase: _controller.value,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isNormal ? Icons.arrow_upward : Icons.warning_amber,
                size: 14,
                color: isNormal ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(width: 4),
              Text(
                isNormal ? "Resting Normal" : "Outside Normal Range",
                style: TextStyle(
                  color: isNormal ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BloodOxygenCard extends StatefulWidget {
  final int spo2;
  final int heartRate;

  const _BloodOxygenCard({required this.spo2, required this.heartRate});

  @override
  State<_BloodOxygenCard> createState() => _BloodOxygenCardState();
}

class _BloodOxygenCardState extends State<_BloodOxygenCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationForBpm(widget.heartRate),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _BloodOxygenCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.heartRate != widget.heartRate) {
      _controller.duration = _durationForBpm(widget.heartRate);
    }
  }

  // Pulse-ox waveform pulses in time with the heartbeat, so it's paced off
  // the same heart rate value as the ECG card — same formula as
  // _HeartRateCardState so the two traces stay in sync.
  Duration _durationForBpm(int bpm) {
    final safeBpm = bpm > 0 ? bpm : 75;
    final ms = (90000 / safeBpm).round().clamp(600, 3000);
    return Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spo2 = widget.spo2;
    final healthy = spo2 == 0 || spo2 >= 95;

    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.air, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                "BLOOD OXYGEN",
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "$spo2%",
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRect(
            child: SizedBox(
              height: 70,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _PlethWavePainter(
                      color: AppColors.primary,
                      heartRate: widget.heartRate,
                      phase: _controller.value,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              healthy ? "Healthy Range" : "Below Healthy Range",
              style: TextStyle(
                color: healthy ? AppColors.success : AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  final String bandId;
  final int steps;
  final int goal;

  const _StepsCard({
    required this.bandId,
    required this.steps,
    required this.goal,
  });

  Future<void> _editGoal(BuildContext context) async {
    final controller = TextEditingController(text: goal.toString());

    final newGoal = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Edit Daily Step Goal"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Goal (steps)"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (newGoal != null && newGoal > 0) {
      await FirebaseFirestore.instance
          .collection('bands')
          .doc(bandId)
          .update({'stepGoal': newGoal});
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_walk, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                "DAILY STEPS",
                style: TextStyle(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        backgroundColor: AppColors.background,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                    const Icon(Icons.directions_walk, color: AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Text(
                "$steps",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
              Text(
                " / $goal",
                style: const TextStyle(fontSize: 16, color: AppColors.mutedText),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editGoal(context),
              icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
              label: const Text("Edit Goal", style: TextStyle(color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// There's no accelerometer/motion field in the firmware payload today —
/// only heartRate, spo2, fallDetected, status and lastUpdated get sent.
/// This reuses the same lastUpdated timestamp as a stand-in until real
/// motion tracking is added to firmware; it's honest about that in the
/// comment here rather than inventing a fake sensor reading.
class _LastMovementCard extends StatelessWidget {
  final String lastSyncText;

  const _LastMovementCard({required this.lastSyncText});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline, color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    "LAST MOVEMENT",
                    style: TextStyle(
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                lastSyncText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Real ECG-style trace: flat baseline, a small rounded P bump, another
/// flat stretch, then a sharp Q-R-S spike (down, tall spike up, down
/// past baseline), back to flat until the next beat — matching an
/// actual heart-rate monitor readout. Two things make it read as "live"
/// instead of a static repeating image:
///   1. It continuously scrolls left in real time, driven by [phase]
///      (0..1, supplied every frame by an AnimationController whose
///      speed is tied to heartRate).
///   2. Each individual beat's spike height varies slightly from the
///      next (deterministically, via [_beatVariation]) instead of every
///      beat being an identical stamped-out copy — the natural
///      beat-to-beat jitter you see on a real hospital monitor.
/// The BPM value still controls FREQUENCY (how tightly beats are
/// spaced) on top of that per-beat variation.
class _WavePainter extends CustomPainter {
  final Color color;
  final int heartRate;
  final double phase;

  const _WavePainter({
    required this.color,
    required this.heartRate,
    required this.phase,
  });

  // Deterministic pseudo-random value in [0, 1) for a given beat index —
  // same index always gives the same value, so a beat's height doesn't
  // flicker frame to frame, but different beats naturally differ.
  double _beatVariation(int seed) {
    final v = math.sin(seed * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final midY = h * 0.55;

    final safeBpm = heartRate > 0 ? heartRate : 75;

    // Frequency scales directly with BPM: beats sit closer together as
    // the rate climbs, further apart (more flat baseline between each
    // one) as it drops.
    final cycles = (2 + (safeBpm - 50) * 0.05).clamp(2.0, 7.0);
    final cycleWidth = w / cycles;

    // Amplitude scales with how far the reading sits from a calm ~75 bpm —
    // a low heart rate draws a flatter trace, a high one a taller, more
    // urgent-looking one. 1.0 at 75 bpm keeps that baseline unchanged.
    final intensity = (1.0 + (safeBpm - 75) / 100).clamp(0.5, 1.6);

    // Base heights for each part of the complex — actual per-beat
    // heights below are these scaled by _beatVariation, so beats vary
    // (some taller, some shorter) instead of every one being identical.
    final basePWave = h * 0.12 * intensity;
    final baseQDip = h * 0.10 * intensity;
    final baseRSpike = h * 0.46 * intensity;
    final baseSDip = h * 0.22 * intensity;

    final shift = phase * cycleWidth;

    final path = Path();
    double x = -cycleWidth + shift;
    path.moveTo(x, midY);

    // Running beat index so each beat gets its own (but stable) random
    // seed regardless of scroll position.
    int beatIndex = -1;

    while (x < w + cycleWidth) {
      beatIndex++;

      // Scale factors in roughly [0.75, 1.25] — enough variation to look
      // natural without any single beat looking broken.
      final rScale = 0.75 + _beatVariation(beatIndex) * 0.33;
      final pScale = 0.75 + _beatVariation(beatIndex + 100) * 0.5;
      final sScale = 0.75 + _beatVariation(beatIndex + 200) * 0.5;

      final pWaveHeight = basePWave * pScale;
      final qDip = baseQDip * rScale;
      final rSpike = baseRSpike * rScale;
      final sDip = baseSDip * sScale;

      // Flat baseline leading into the beat.
      path.lineTo(x + cycleWidth * 0.10, midY);

      // Small rounded P wave bump.
      path.quadraticBezierTo(
        x + cycleWidth * 0.14,
        midY - pWaveHeight,
        x + cycleWidth * 0.18,
        midY,
      );

      // Flat stretch before the sharp spike.
      path.lineTo(x + cycleWidth * 0.28, midY);

      // Sharp Q-R-S complex — straight edges, not curves, for the crisp
      // "monitor spike" look instead of a soft rounded bump.
      path.lineTo(x + cycleWidth * 0.32, midY + qDip);
      path.lineTo(x + cycleWidth * 0.37, midY - rSpike);
      path.lineTo(x + cycleWidth * 0.42, midY + sDip);
      path.lineTo(x + cycleWidth * 0.47, midY);

      // Flat baseline out to the next beat.
      path.lineTo(x + cycleWidth, midY);

      x += cycleWidth;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.heartRate != heartRate;
}

/// Plethysmograph-style SpO2 trace: a smooth rounded pulse with a small
/// dicrotic notch on the downslope, unlike the sharp ECG spike in
/// _WavePainter — this is what a real pulse-ox waveform looks like.
class _PlethWavePainter extends CustomPainter {
  final Color color;
  final int heartRate;
  final double phase;

  const _PlethWavePainter({
    required this.color,
    required this.heartRate,
    required this.phase,
  });

  double _beatVariation(int seed) {
    final v = math.sin(seed * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final baseline = h * 0.82;

    final safeBpm = heartRate > 0 ? heartRate : 75;

    final cycles = (2 + (safeBpm - 50) * 0.05).clamp(2.0, 7.0);
    final cycleWidth = w / cycles;

    final baseAmp = h * 0.55;

    final shift = phase * cycleWidth;

    final path = Path();
    double x = -cycleWidth + shift;
    path.moveTo(x, baseline);

    int beatIndex = -1;

    while (x < w + cycleWidth) {
      beatIndex++;

      final ampScale = 0.8 + _beatVariation(beatIndex) * 0.3;
      final amp = baseAmp * ampScale;

      // Flat baseline right before the beat starts.
      path.lineTo(x + cycleWidth * 0.06, baseline);

      // Fast systolic upstroke to the main peak.
      path.cubicTo(
        x + cycleWidth * 0.12,
        baseline - amp * 0.5,
        x + cycleWidth * 0.16,
        baseline - amp,
        x + cycleWidth * 0.22,
        baseline - amp,
      );

      // Sharp fall off the peak toward the dicrotic notch.
      path.cubicTo(
        x + cycleWidth * 0.27,
        baseline - amp * 0.5,
        x + cycleWidth * 0.30,
        baseline - amp * 0.42,
        x + cycleWidth * 0.34,
        baseline - amp * 0.45,
      );

      // Small secondary dicrotic bump.
      path.cubicTo(
        x + cycleWidth * 0.38,
        baseline - amp * 0.5,
        x + cycleWidth * 0.42,
        baseline - amp * 0.3,
        x + cycleWidth * 0.48,
        baseline - amp * 0.22,
      );

      // Slow diastolic decay back to baseline before the next beat.
      path.cubicTo(
        x + cycleWidth * 0.62,
        baseline - amp * 0.05,
        x + cycleWidth * 0.80,
        baseline,
        x + cycleWidth,
        baseline,
      );

      x += cycleWidth;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PlethWavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.heartRate != heartRate;
}