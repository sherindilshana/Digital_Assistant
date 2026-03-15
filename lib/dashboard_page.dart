import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart'; // REQUIRED

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isServiceActive = false;

  @override
  void initState() {
    super.initState();
    // 1. Run the Auto-Setup Wizard immediately on startup
    _runAutoSetup();
  }

  Future<void> _runAutoSetup() async {
    // STEP 1: Battery Optimizations
    var batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (!batteryStatus.isGranted) {
       await Permission.ignoreBatteryOptimizations.request();
    }

    // STEP 2: Overlay Permission
    bool overlayStatus = await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayStatus) {
      await FlutterOverlayWindow.requestPermission();
    }

    // NEW: Step 3: Request Camera & Mic here so the bubble has permission later
    await [
      Permission.camera,
      Permission.microphone,
    ].request();

    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final bool isActive = await FlutterOverlayWindow.isActive();
    setState(() => _isServiceActive = isActive);
  }

  Future<void> _toggleAssistant() async {
    // Double check permissions just in case
    final bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }

    if (_isServiceActive) {
      await FlutterOverlayWindow.closeOverlay();
      setState(() => _isServiceActive = false);
    } else {
      await FlutterOverlayWindow.showOverlay(
        height: 100,
        width: 100,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        startPosition: const OverlayPosition(200, 200),
      );
      setState(() => _isServiceActive = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Control Center"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.smart_toy, size: 80, color: Color(0xFF6A11CB)),
            const SizedBox(height: 20),
            Text(
              _isServiceActive ? "Assistant Active 🟢" : "Assistant Sleeping 💤",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            // Helpful note for the user
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "If the assistant stops, open this app to fix it automatically.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 40),
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
          ],
        ),
      ),
    );
  }
}