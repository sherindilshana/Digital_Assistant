import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../dashboard_page.dart';

class SetupGuide extends StatelessWidget {
  const SetupGuide({super.key});

  Future<void> openOverlayPermission() async {
    await FlutterOverlayWindow.requestPermission();
  }

  Future<void> openAccessibilitySettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.ACCESSIBILITY_SETTINGS',
    );
    await intent.launch();
  }

  Widget stepNumber(int number) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color:  Color.fromARGB(255, 1, 71, 193),
      ),
      alignment: Alignment.center,
      child: Text(
        number.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget stepContainer({
    required int step,
    required String title,
    required String malayalam,
    required String description,
    required String image,
    String? buttonText,
    VoidCallback? onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              stepNumber(step),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      malayalam,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),

          const SizedBox(height: 15),

          Image.asset(image, height: 240, fit: BoxFit.contain),

          const SizedBox(height: 15),

          if (buttonText != null && onPressed != null)
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor:  Color.fromARGB(255, 1, 71, 193),
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        title: const Text("Assistant Setup"),
        centerTitle: true,
        backgroundColor:  Color.fromARGB(255, 1, 71, 193),
        foregroundColor: Colors.white,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              const SizedBox(height: 10),

              const Icon(
                Icons.settings_accessibility,
                size: 90,
                color:  Color.fromARGB(255, 1, 71, 193),
              ),

              const SizedBox(height: 20),

              const Text(
                "Enable Assistant Permissions",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 30),

              // STEP 1
              stepContainer(
                step: 1,
                title: "Enable Draw Over Other Apps",
                malayalam: "മറ്റ് ആപ്പുകളുടെ മുകളിൽ കാണാൻ അനുമതി നൽകുക",
                description:
                    "Turn ON permission for digital_assistant so the floating assistant can appear.",
                image: "assets/setup/overlay_permission.jpeg",
                buttonText: "Open Permission",
                onPressed: openOverlayPermission,
              ),

              // STEP 2
              stepContainer(
                step: 2,
                title: "Enable Accessibility Service",
                malayalam: "ആക്സസിബിലിറ്റി സർവീസ് ഓൺ ചെയ്യുക",
                description:
                    "Find digital_assistant in the list and turn the switch ON.",
                image: "assets/setup/accessibility_permission.jpeg",
                buttonText: "Open Accessibility",
                onPressed: openAccessibilitySettings,
              ),
              const SizedBox(height: 10),
              stepContainer(
                step: 3,
                title: "Confirm Permission",
                malayalam: "അനുമതി നൽകാൻ OK അമർത്തുക",
                description:
                    "When Android asks 'Use digital_assistant?', press OK to allow screen reading.",
                image: "assets/setup/accessibility_popup.jpeg",
              ),

              const SizedBox(height: 10),

              // Continue Button
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const DashboardPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "Continue",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
