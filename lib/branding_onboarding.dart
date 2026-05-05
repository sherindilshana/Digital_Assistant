import 'package:digital_assistant/dashboard_page.dart';
import 'package:digital_assistant/setup/setup_guide.dart';
import 'package:flutter/material.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final LiquidController _controller = LiquidController();
  int currentPage = 0;

  Timer? _autoSwipeTimer;

  final List<Map<String, String>> pagesData = [
    {
      "image": "assets/images/onboarding/robot_bridge.png",
      "title": "Bridge the Gap",
      "subtitle": "Assisting elderly in embracing technology.",
      "bgColor": "#215EFD", // Deep Blue
      "waveColor": "#64B5F6", // Lighter Blue for wave
    },
    {
      "image": "assets/images/onboarding/robot_translate.png",
      "title": "Translate Instantly",
      "subtitle": "Bridge languages effortlessly.",
      "bgColor": "#29B6F6", // Cyan/Light Blue
      "waveColor": "#81D4FA", // Lighter Cyan for wave
    },
    {
      "image": "assets/images/onboarding/robot_listen.png",
      "title": "Listen to Translation",
      "subtitle": "Hear translations in your language.",
      "bgColor": "#215EFD", // Deep Blue
      "waveColor": "#64B5F6", // Lighter Blue for wave
    },
  ];

  @override
  void initState() {
    super.initState();

    // 🚀 Start auto swipe AFTER widget is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoSwipe();
    });
  }


  @override
  void dispose() {
    _autoSwipeTimer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          LiquidSwipe(
            pages: pagesData.map((data) => _buildCustomPage(data)).toList(),
            liquidController: _controller,
            enableLoop: false,
            fullTransitionValue: 600,
            waveType: WaveType.liquidReveal,
            slideIconWidget: null, // ❌ remove swipe icon
            onPageChangeCallback: (index) {
              setState(() => currentPage = index);
            },
          ),

          // ✅ Get Started button ONLY on last page
          if (currentPage == pagesData.length - 1)
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('seenOnboarding', true);

                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const SetupGuide()),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF015DE3),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: const Text(
                  "Get Started",
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _startAutoSwipe() {
    _autoSwipeTimer = Timer.periodic(const Duration(milliseconds: 2000), (
      timer,
    ) {
      if (currentPage < pagesData.length - 1) {
        currentPage++;
        _controller.animateToPage(
          page: currentPage,
          duration: 500, // smooth & elderly-friendly
        );
      } else {
        timer.cancel(); // stop on last page
      }
    });
  }

  // --- THE CUSTOM PAGE BUILDER ---
  Widget _buildCustomPage(Map<String, String> data) {
    // Parse colors
    Color bgColor = Color(int.parse(data['bgColor']!.replaceAll('#', '0xff')));
    Color waveColor = Color(int.parse(data['waveColor']!.replaceAll('#', '0xff')));

    return Container(
      width: double.infinity,
      color: bgColor, // Main background color
      child: Stack(
        children: [
          // 1. The Wave Background (Bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 250, // Height of the wave area
            child: CustomPaint(
              painter: WavePainter(color: waveColor),
            ),
          ),

          // 2. The Content (Robot + Text)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
             
              // Illustration (Flexible to fit screen)
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Image.asset(
                    data['image']!,
                    fit: BoxFit.contain, // Ensures the robot is never cut off
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Title & Subtitle
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    children: [
                      Text(
                        data['title']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: "Arial",
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        data['subtitle']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
             
              const SizedBox(height: 80), // Space for button/bottom
            ],
          ),
        ],
      ),
    );
  }
}

// --- CUSTOM PAINTER FOR THE WAVE (The Magic Part) ---
class WavePainter extends CustomPainter {
  final Color color;
  WavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. First Wave (Lighter, taller)
    final paint1 = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, size.height);
    path1.lineTo(0, size.height * 0.5); // Start mid-way up the wave box

    // Draw S-curve
    path1.cubicTo(
      size.width * 0.25, size.height * 0.4, // Control point 1
      size.width * 0.75, size.height * 0.6, // Control point 2
      size.width, size.height * 0.5         // End point
    );

    path1.lineTo(size.width, size.height);
    path1.close();
    canvas.drawPath(path1, paint1);
   
    // 2. Second Wave (Darker, shorter, overlaps the first)
    final paint2 = Paint()
      ..color = Colors.white.withOpacity(0.15) // Subtle white overlay
      ..style = PaintingStyle.fill;
     
    final path2 = Path();
    path2.moveTo(0, size.height);
    path2.lineTo(0, size.height * 0.65);
    path2.cubicTo(
      size.width * 0.3, size.height * 0.85,
      size.width * 0.6, size.height * 0.55,
      size.width, size.height * 0.7
    );
    path2.lineTo(size.width, size.height);
    path2.close();
   
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


