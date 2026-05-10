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
    // Smart navigation: find next EMPTY field (skips already-filled ones)
    else if (message == "FindNextField") {
      await _findAndProcessNextField();
    }
    // Fallback: get fields by focus context
    else if (message == "GetFormFields") {
      await _getFormFieldsFromNative();
    }
    // --- HANDLE CAMERA FROM MAIN APP ---
    else if (message == "OPENCAMERA") {
      await _handleMainAppCamera();
    } else if (message.toString().startsWith("InjectText:")) {
      String textToInject = message.toString().substring(11);
      await _injectTextToNative(textToInject);
    }
    // --- EMAIL_POPUP: Ask Kotlin to show the native account picker ---
    else if (message == "TRIGGER_EMAIL_POPUP") {
      await _triggerEmailPopup();
    }
    // --- AUTO_WAIT: Tell Kotlin to listen for SMS OTP ---
    else if (message == "START_OTP_WATCH") {
      await _startOtpWatch();
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
      
      // 4. 🛡️ CRITICAL FIX: Push to background INSTEAD of closing.
      // SystemNavigator.pop() kills the isolate port — use moveTaskToBack instead.
      await platform.invokeMethod('moveTaskToBack');

    } catch (e) {
      try {
        const platform2 = MethodChannel('com.example.digital_assistant/accessibility');
        await platform2.invokeMethod('moveTaskToBack');
      } catch (_) {}
    }
  }
}

// --- SMART HELPER: Finds next EMPTY field, skips already-filled ones ---
Future<void> _findAndProcessNextField() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    // 🛡️ ALWAYS ask for the next EMPTY field first.
    // This skips already-filled fields like Aadhaar, Name, DOB.
    final String? nextEmpty = await platform.invokeMethod('findNextEmptyField');

    if (nextEmpty != null && nextEmpty.isNotEmpty) {
      // Found an empty field — send it to the bubble to decide CAMERA/VOICE/etc.
      await FlutterOverlayWindow.shareData("FORM_FIELDS_RESULT:$nextEmpty");
    } else {
      // All fields are filled! Tell the user the form is complete.
      await FlutterOverlayWindow.shareData("FORM_COMPLETE:");
    }
  } catch (e) {
    await FlutterOverlayWindow.shareData("FORM_FIELDS_ERROR:$e");
  }
}

// --- FALLBACK HELPER: Gets fields by focus context ---
Future<void> _getFormFieldsFromNative() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    String formFields = await platform.invokeMethod('getFormFields');
    await FlutterOverlayWindow.shareData("FORM_FIELDS_RESULT:$formFields");
  } catch (e) {
    await FlutterOverlayWindow.shareData("FORM_FIELDS_ERROR:$e");
  }
}

// --- EMAIL POPUP: Triggers native Android account picker ---
Future<void> _triggerEmailPopup() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    final String? email = await platform.invokeMethod('showEmailPicker');
    if (email != null && email.isNotEmpty) {
      // 🛡️ CRITICAL FIX: Push Flutter app to background so Form Page becomes active
      await platform.invokeMethod('moveTaskToBack');
      
      // Wait for the OS to switch apps and render the form page
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Inject the selected email
      await platform.invokeMethod('injectText', {'text': email});
      
      // Wait for text to settle, then jump to the next empty field
      await Future.delayed(const Duration(milliseconds: 900));
      await _findAndProcessNextField();
    } else {
      // If user cancelled, just go back to form
      await platform.invokeMethod('moveTaskToBack');
      await FlutterOverlayWindow.shareData("FORM_FIELDS_RESULT:[FIELD]: next field");
    }
  } catch (e) {
    print("Email Popup Error: $e");
    try { await platform.invokeMethod('moveTaskToBack'); } catch (_) {}
    await FlutterOverlayWindow.shareData("FORM_FIELDS_RESULT:[FIELD]: next field");
  }
}

// --- OTP WATCH: Kotlin listens for SMS for auto-fill ---
Future<void> _startOtpWatch() async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    // Kotlin side will handle the notification listener
    // and call injectText automatically when OTP arrives
    await platform.invokeMethod('startOtpWatch');
  } catch (e) {
    print("OTP Watch Error: $e");
  }
}

// --- HELPER: Asks Kotlin to type the text, then auto-advance to next empty field ---
Future<void> _injectTextToNative(String text) async {
  const platform = MethodChannel('com.example.digital_assistant/accessibility');
  try {
    await platform.invokeMethod('injectText', {'text': text});
    // 🛡️ AUTO-ADVANCE: After injecting voice text, wait briefly for the form
    // to register the value, then automatically move to the next empty field.
    await Future.delayed(const Duration(milliseconds: 900));
    await _findAndProcessNextField();
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
