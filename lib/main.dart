import 'dart:ui'; // Required for Port
import 'dart:isolate'; // Required for Port
import 'dart:async'; // Required for Timeout
import 'package:digital_assistant/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'overlay_bubble.dart';
import 'services/ocr_service.dart';
import 'services/api_service.dart'; // <--- NEW: Import the Backend Bridge
import 'package:digital_assistant/services/source_reliability_service.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayBubble()),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ CHECK: Has user seen onboarding?
  final prefs = await SharedPreferences.getInstance();
  final bool seen = prefs.getBool('seenOnboarding') ?? false;

  runApp(MyApp(seenOnboarding: seen)); // Pass result to MyApp

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
      await _performHybridScan(); // Your existing Translation
    }
    // --- NEW: Handle Form Assistant Commands ---
    else if (message == "GetFormFields") {
      await _getFormFieldsFromNative();
    }
    // --- NEW: HANDLE CAMERA FROM MAIN APP ---
    else if (message == "OPENCAMERA") {
      await _handleMainAppCamera();
    } else if (message.toString().startsWith("InjectText:")) {
      String textToInject = message.toString().substring(11);
      await _injectTextToNative(textToInject);
    }
  });
}

Future<void> _handleMainAppCamera() async {
  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.camera);

  if (image != null) {
    final inputImage = InputImage.fromFilePath(image.path);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    if (recognizedText.text.trim().isEmpty) return;

    try {
      final Map<String, dynamic> idDetails = await ApiService.getUniversalScanData(recognizedText.text);
      const platform = MethodChannel('com.example.digital_assistant/accessibility');

      // 1. 🛡️ TRIGGER AUTO-FILL IMMEDIATELY
      await platform.invokeMethod('autoFillAllFields', {'data_map': idDetails});
      await FlutterOverlayWindow.shareData("CAMERA_TEXT_READY:");

      // 2. 🛡️ THE "ANCHOR" DELAY
      // We must keep the app ALIVE for at least 1.5 seconds.
      // This ensures Android doesn't kill the focus while Kotlin is searching for the form.
      await Future.delayed(const Duration(milliseconds: 4500));

      // 3. 🛡️ PERFORM THE SWEEP
      final String? nextEmpty = await platform.invokeMethod('findNextEmptyField');
      
      if (nextEmpty != null) {
        // Change the bubble to Microphone BEFORE closing
        await FlutterOverlayWindow.shareData("PROCESS_NEXT_FIELD:$nextEmpty");
        // Tiny extra buffer to ensure message delivery
        await Future.delayed(const Duration(milliseconds: 600));
      } 
      else {
        await FlutterOverlayWindow.shareData("CAMERA_TEXT_READY:");
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // 4. NOW CLOSE
      SystemNavigator.pop();

    } catch (e) {
      SystemNavigator.pop();
    }
  }
}

// --- NEW HELPER: Asks Kotlin for the fields and sends it back to the bubble ---
Future<void> _getFormFieldsFromNative() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    String formFields = await platform.invokeMethod('getFormFields');
    await FlutterOverlayWindow.shareData("FORM_FIELDS_RESULT:$formFields");
  } catch (e) {
    await FlutterOverlayWindow.shareData("FORM_FIELDS_ERROR:$e");
  }
}

// --- NEW HELPER: Asks Kotlin to type the text ---
Future<void> _injectTextToNative(String text) async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    await platform.invokeMethod('injectText', {'text': text});
  } catch (e) {
    print("Main App: Inject Error: $e");
  }
}

// --- HYBRID BACKGROUND LOGIC (Text + OCR + Backend) ---
Future<void> _performHybridScan() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  StringBuffer scannedTextBuffer = StringBuffer(); // Collects raw English text

  try {
    print("Main App: Starting Hybrid Scan...");

    // --- STEP 1: GET LAYOUT TEXT (Fast Accessibility Scan) ---
    try {
      // We keep your 2-second timeout to prevent freezing on layout scan
      String layoutText = await platform
          .invokeMethod('getScreenText')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              print("Main App: Layout scan timed out!");
              return "";
            },
          );

      if (layoutText.isNotEmpty && layoutText.length > 5) {
        scannedTextBuffer.writeln("--- LAYOUT TEXT ---");
        scannedTextBuffer.writeln(layoutText);
        scannedTextBuffer.writeln("\n");
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
          scannedTextBuffer.writeln("--- IMAGE TEXT ---");
          scannedTextBuffer.writeln(imageText);
        } else {
          print("Main App: OCR found no text pixels.");
        }
      } else {
        print("Main App: Screenshot failed (null path).");
      }
    } catch (e) {
      print("OCR Error: $e");
      scannedTextBuffer.writeln("[Image reading skipped: $e]");
    }

    // --- STEP 3: SEND TO BACKEND & TRANSLATE (NEW LOGIC) ---
    String rawEnglish = scannedTextBuffer.toString();
    String currentApp = await platform.invokeMethod('getCurrentApp');
    // SOURCE RELIABILITY CHECK
    String reliabilityResult = await SourceReliabilityService.checkSource(
      rawEnglish,
      currentApp,
      
    );

    // Check if we actually found any text
    if (rawEnglish.trim().isEmpty) {
      print("Main App: No text found.");
      await FlutterOverlayWindow.shareData("RESULT:No text found on screen.");
      return;
    }

    print("Main App: Sending ${rawEnglish.length} chars to Backend...");

    // Optional: Tell the user we are working (Updates the bubble text)
    await FlutterOverlayWindow.shareData(
      "RESULT:Translating...\n(Please wait)",
    );

    // CALL THE API (Sends text to Laptop -> Gemini/Offline -> Back)
    String translatedResult = await ApiService.sendToBackend(rawEnglish);
    translatedResult =
    "$reliabilityResult\n\n$translatedResult";

    print("Main App: Translation received.");

    // Send the FINAL MALAYALAM RESULT to the bubble
    await FlutterOverlayWindow.shareData("RESULT:$translatedResult");
  } catch (e) {
    print("Main App General Error: $e");
    await FlutterOverlayWindow.shareData(
      "RESULT:Error: Could not scan screen.\n$e",
    );
  }
}

class MyApp extends StatelessWidget {
  final bool seenOnboarding; // Receive the value here
  const MyApp({super.key, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Load SplashScreen first, passing the boolean
      home: SplashScreen(seenOnboarding: seenOnboarding),
    );
  }
}
