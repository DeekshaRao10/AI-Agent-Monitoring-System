import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'create_family_screen.dart';
import 'join_family_screen.dart';

class FamilyChoiceScreen extends StatelessWidget {
  const FamilyChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.arrow_back,
                color: AppColors.black,
              ),

              const SizedBox(height: 20),

              const Text(
                "Set up your family",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Choose how you want to get started with SafeBand.",
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 30),

              _familyOptionCard(
                context,
                icon: Icons.groups,
                iconColor: AppColors.primary,
                title: "Create a family",
                subtitle:
                    "I'm setting up SafeBand for my family",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateFamilyScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              _familyOptionCard(
                context,
                icon: Icons.login,
                iconColor: Colors.orange,
                title: "Join a family",
                subtitle:
                    "I have an invite code",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const JoinFamilyScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _familyOptionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),

      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),

        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),

        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  iconColor.withOpacity(0.15),
              child: Icon(
                icon,
                color: iconColor,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}