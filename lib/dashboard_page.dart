import 'dart:isolate';
import 'dart:ui';
import 'package:digital_assistant/services/source_reliability_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'universal_reader.dart';
import 'services/api_service.dart';
import 'services/ocr_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // ---------------------------------------------------------------------------
  // STATE VARIABLES
  // ---------------------------------------------------------------------------
  bool _isServiceActive = false;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    // Combined Auto-Setup from both versions
    _runAutoSetup();
  }

  // ---------------------------------------------------------------------------
  // PERMISSIONS & INITIALIZATION
  // ---------------------------------------------------------------------------
  Future<void> _runAutoSetup() async {
    // STEP 1: Fix Battery Killing (Your requirement)
    var batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (!batteryStatus.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // STEP 2: Overlay Permission (Your requirement)
    bool overlayStatus = await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayStatus) {
      await FlutterOverlayWindow.requestPermission();
    }

    // STEP 3: Request Camera & Mic for the Bubble/Manual Scan (Merged requirement)
    await [
      Permission.camera,
      Permission.microphone,
    ].request();

    // STEP 4: Check Service Status
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final bool isActive = await FlutterOverlayWindow.isActive();
    setState(() => _isServiceActive = isActive);
  }

  // ---------------------------------------------------------------------------
  // ASSISTANT LOGIC (Your Overlay Toggle)
  // ---------------------------------------------------------------------------
  Future<void> _toggleAssistant() async {
    final bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }

    if (_isServiceActive) {
      await FlutterOverlayWindow.closeOverlay();
      setState(() => _isServiceActive = false);
    } else {
      // Combined overlay settings (using your refined height/width)
      await FlutterOverlayWindow.showOverlay(
        height: 90,
        width: 90,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        startPosition: const OverlayPosition(200, 200),
      );
      setState(() => _isServiceActive = true);
    }
  }

  // ---------------------------------------------------------------------------
  // SCANNING & OCR LOGIC (Her Manual Scan Feature)
  // ---------------------------------------------------------------------------
  Future<void> _handleManualFormScan() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);

    if (photo != null) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // 1. OCR (English)
        String englishText = await OcrService.processImage(photo.path);
        String reliability =
              await SourceReliabilityService.checkSource(englishText, "com.example.digital_assistant");
        englishText = "$reliability\n\n$englishText";
        // 2. Translation (Malayalam) - Using sendToBackend from her logic
        String translatedResult = await ApiService.sendToBackend(englishText);

        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog

        // 3. Open Universal Reader Page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UniversalReaderPage(rawText: translatedResult),
          ),
        );
      } catch (e) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD UI (Merging both Visual designs)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Control Center"), centerTitle: true),
      body: Center(
        child: SingleChildScrollView( // Added scroll for smaller screens
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status Icon
              const Icon(Icons.smart_toy, size: 80, color: Color(0xFF6A11CB)),
              const SizedBox(height: 20),

              // Status Text
              Text(
                _isServiceActive ? "Assistant Active 🟢" : "Assistant Sleeping 💤",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // User Instructions
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "If the assistant stops, open this app to fix it automatically.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 40),

              // Your Feature: Overlay Toggle Button
              ElevatedButton(
                onPressed: _toggleAssistant,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  backgroundColor: _isServiceActive ? Colors.redAccent : const Color(0xFF6A11CB),
                ),
                child: Text(
                  _isServiceActive ? "Stop Assistant" : "Start Assistant",
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              
              const SizedBox(height: 20),

              // Her Feature: Manual Scan Button
              ElevatedButton.icon(
                onPressed: _handleManualFormScan,
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                label: const Text(
                  "Scan Physical Paper",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2575FC),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}