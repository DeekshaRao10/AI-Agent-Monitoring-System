import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/primary_button.dart';
import 'signup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() =>
      _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();

  int currentIndex = 0;

  final pages = [
    {
      "image": "assets/images/fall_detection.png",
      "title": "Fall Detection",
      "subtitle": "Automatic alerts when a fall is detected",
    },
    {
      "image": "assets/images/heart_rate.png",
      "title": "Heart Rate Monitoring",
      "subtitle":
          "Track heart rate continuously and detect abnormalities",
    },
    {
      "image": "assets/images/oxygen_level.png",
      "title": "Blood Oxygen Level",
      "subtitle":
          "Monitor oxygen levels and receive health alerts",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea//prevents overlap
      (
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignupScreen(),
                  ),
                ),
                child: const Text(
                  "Skip",
                  style: TextStyle(
                    color: Color(0xFF006D6F),
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder//Creates swipeable pages.
              (
                controller: controller,
                itemCount: pages.length,

                onPageChanged: (index) =>
                    setState(() => currentIndex = index),

                itemBuilder: (context, index) {
                  final page = pages[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                    ),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        ClipOval(
                          child: Image.asset(
                            page["image"]!,
                            width: 280,
                            height: 280,
                            fit: BoxFit.cover,
                          ),
                        ),

                        const SizedBox(height: 40),

                        Text(
                          page["title"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          page["subtitle"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (index) => Container(
                  margin: const EdgeInsets.all(4),
                  width:
                      currentIndex == index ? 12 : 8,
                  height:
                      currentIndex == index ? 12 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: currentIndex == index
                        ? const Color(0xFF006D6F)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 24,
              ),
              child: PrimaryButton(
                text: currentIndex ==
                        pages.length - 1
                    ? "Get Started"
                    : "Next",
                onPressed: () {
                  if (currentIndex <
                      pages.length - 1) {
                    controller.nextPage(
                      duration: const Duration(
                          milliseconds: 300),
                      curve: Curves.ease,
                    );
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SignupScreen(),
                      ),
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}