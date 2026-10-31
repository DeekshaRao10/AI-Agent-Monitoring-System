import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../services/family_service.dart';
import 'family_created_screen.dart';

class CreateFamilyScreen extends StatelessWidget {
  CreateFamilyScreen({super.key});

  final TextEditingController familyController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups,
                  color: AppColors.white,
                  size: 45,
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                "Create Family",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Enter a family name to create your SafeBand family group.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 35),

              AppTextField(
                controller: familyController,
                hintText: "Family Name",
                prefixIcon: Icons.family_restroom,
              ),

              const SizedBox(height: 30),

              PrimaryButton(
                text: "Create Family",
                onPressed: () async {
                  if (familyController.text
                      .trim()
                      .isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please enter a family name",
                        ),
                      ),
                    );
                    return;
                  }

                  try {
                    final result =
                        await FamilyService()
                            .createFamily(
                      familyController.text
                          .trim(),
                    );

                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FamilyCreatedScreen(
                            familyName:
                                familyController
                                    .text
                                    .trim(),
                            inviteCode:
                                result[
                                    'inviteCode']!,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content:
                            Text(e.toString()),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}