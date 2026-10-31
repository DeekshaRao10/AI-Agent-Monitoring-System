import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../services/family_service.dart';
import '../../pairing/screens/pair_scan_screen.dart';
import '../../bands/screens/dashboard_screen.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() =>
      _JoinFamilyScreenState();
}

class _JoinFamilyScreenState
    extends State<JoinFamilyScreen> {

  final TextEditingController codeController =
      TextEditingController();

  Map<String, dynamic>? familyData;

  bool loading = false;

  Future<void> searchFamily() async {
    if (codeController.text.trim().length != 6) {
      return;
    }

    setState(() {
      loading = true;
    });

    final result =
        await FamilyService().getFamilyByCode(
      codeController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      familyData = result;
      loading = false;
    });

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Invalid Invite Code",
          ),
        ),
      );
    }
  }
void showBandDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),

      title: const Text(
        "Do you have a SafeBand?",
        textAlign: TextAlign.center,
      ),

      content: Text(
        "You joined ${familyData!['familyName']}.\n\nWould you like to pair your band now?",
        textAlign: TextAlign.center,
      ),

      actionsAlignment: MainAxisAlignment.center,

      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.pop(dialogContext);

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const DashboardScreen(),
              ),
            );
          },
          child: const Text("No"),
        ),

        ElevatedButton(
          onPressed: () {
            Navigator.pop(dialogContext);

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const PairScanScreen(),
              ),
            );
          },
          child: const Text("Yes"),
        ),
      ],
    ),
  );
}  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 50,
      height: 60,
      textStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.black,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          children: [
            const SizedBox(height: 20),

            const Text(
              "Join your family",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              "Enter the 6-digit invite code provided by your family organizer",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 35),

            Pinput(
              controller: codeController,
              length: 6,
              defaultPinTheme: defaultPinTheme,
              keyboardType: TextInputType.number,
              onCompleted: (value) {
                searchFamily();
              },
            ),

            const SizedBox(height: 30),

            if (loading)
              const CircularProgressIndicator(),

            if (familyData != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                      BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          AppColors.primary,
                      child: const Icon(
                        Icons.groups,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "You're joining",
                            style: TextStyle(
                              color: AppColors.grey,
                            ),
                          ),

                          Text(
                            familyData!['familyName'],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const Text(
                            "Family",
                            style: TextStyle(
                              color: AppColors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            if (familyData != null)
              PrimaryButton(
                text: "Confirm",
                onPressed: () async {
                  try {
                    await FamilyService()
                        .joinFamily(
                      codeController.text.trim(),
                    );

                    if (!mounted) return;

                    showBandDialog();
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
    );
  }
}