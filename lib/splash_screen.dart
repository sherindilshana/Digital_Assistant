import 'dart:async';
import 'package:flutter/material.dart';
import 'branding_onboarding.dart'; // LiquidSwipe screen
import 'dashboard_page.dart';

class SplashScreen extends StatefulWidget {
  final bool seenOnboarding;
  const SplashScreen({super.key, required this.seenOnboarding});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Auto move to onboarding after 2 seconds
    Timer(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => widget.seenOnboarding
              ? const DashboardPage()
              : const OnboardingScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,  // White background like your design
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // Logo
            Image.asset(
              "assets/images/logo.png",  // change to your exact file name
              height: 160,
            ),

            const SizedBox(height: 18),

            // App Name
            /*const Text(
              "ORU KOOTTU",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E40AF), // Deep blue in your image
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 6),

            // Tagline
            const Text(
              "TOGETHER, WE UNDERSTAND",
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF34D399), // Mint green from your image
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),*/
          ],
        ),
      ),
    );
  }
}


