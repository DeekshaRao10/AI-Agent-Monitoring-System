import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../../pairing/screens/pair_scan_screen.dart';
import '../../bands/screens/dashboard_screen.dart';

class FamilyCreatedScreen extends StatelessWidget {
  final String familyName;
  final String inviteCode;

  const FamilyCreatedScreen({
    super.key,
    required this.familyName,
    required this.inviteCode,
  });

  Future<void> _shareCode() async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Join my SafeBand Family!\n\n'
            'Family Name: $familyName\n'
            'Invite Code: $inviteCode',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              const SizedBox(height: 40),

              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.white,
                  size: 50,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "Family Created!",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "Share this invite code with your family members so they can join $familyName.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.grey,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 30),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                      BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      "INVITE CODE",
                      style: TextStyle(
                        color: AppColors.grey,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      inviteCode,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SHARE CODE
              PrimaryButton(
                text: "Share Code",
                onPressed: _shareCode,
              ),

              const SizedBox(height: 12),

              // ADD BAND
              PrimaryButton(
                text: "Add a Band",
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const PairScanScreen(),
                    ),
                  );
                },
              ),

              const Spacer(),

              // GO HOME
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const DashboardScreen(),
                    ),
                  );
                },
                child: const Text(
                  "Go to Home",
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}