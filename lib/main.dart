import 'dart:ui'; // Required for Port
import 'dart:isolate'; // Required for Port
import 'dart:async'; // Required for Timeout
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'overlay_bubble.dart';
import 'dashboard_page.dart';
import 'services/ocr_service.dart'; // <--- NEW: Import your OCR Service

@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayBubble(),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());

  // ✅ THE WORMHOLE FIX (Restored)
  // This keeps the connection alive even if Vivo tries to sleep the app
  _setupPort();
}

void _setupPort() {
  final ReceivePort port = ReceivePort();
  
  // Open the mailbox 'ASSISTANT_PORT'
  IsolateNameServer.removePortNameMapping('ASSISTANT_PORT');
  IsolateNameServer.registerPortWithName(port.sendPort, 'ASSISTANT_PORT');
  
  print("Main App: Mailbox opened.");

  // Listen for messages from the Bubble
  port.listen((message) async {
    if (message == "StartScan") {
      await _performHybridScan(); // <--- UPDATED: Calls the new Hybrid function
    }
  });
}

// --- HYBRID BACKGROUND LOGIC (Text + OCR) ---
Future<void> _performHybridScan() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  StringBuffer finalResult = StringBuffer(); // Buildup the final text here

  try {
    print("Main App: Starting Hybrid Scan...");

    // --- STEP 1: GET LAYOUT TEXT (Fast Accessibility Scan) ---
    try {
      // We keep your 2-second timeout to prevent freezing on layout scan
      String layoutText = await platform.invokeMethod('getScreenText').timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print("Main App: Layout scan timed out!");
          return ""; 
        }
      );
      
      if (layoutText.isNotEmpty && layoutText.length > 5) {
        finalResult.writeln("--- LAYOUT TEXT ---");
        finalResult.writeln(layoutText);
        finalResult.writeln("\n");
      }
    } catch (e) {
      print("Layout Scan Error: $e");
    }

    // --- STEP 2: GET IMAGE TEXT (OCR / Vision Scan) ---
    try {
      print("Main App: requesting screenshot...");
      // 1. Ask Native Android to take a screenshot (Safe Mode)
      final String? imagePath = await platform.invokeMethod('takeScreenshot');
      
      if (imagePath != null) {
        print("Main App: Processing Image at $imagePath...");
        
        // 2. Pass image to your OcrService
        String imageText = await OcrService.processImage(imagePath);
        
        if (imageText.isNotEmpty) {
          finalResult.writeln("--- IMAGE TEXT ---");
          finalResult.writeln(imageText);
        } else {
          print("Main App: OCR found no text pixels.");
        }
      } else {
        print("Main App: Screenshot failed (null path).");
      }
    } catch (e) {
      print("OCR Error: $e");
      finalResult.writeln("[Image reading skipped: $e]");
    }

  } catch (e) {
    print("Main App General Error: $e");
    finalResult.write("Error: Could not scan screen.");
  }

  // --- STEP 3: SEND COMBINED RESULT ---
  String response = finalResult.toString();
  if (response.isEmpty) response = "No text found on screen.";

  print("Main App: Sending response (${response.length} chars)");
  
  // Send back to the bubble to display in the list
  await FlutterOverlayWindow.shareData("RESULT:$response");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const DashboardPage(), // ✅ Loads UI from separate file
    );
  }
}