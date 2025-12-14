import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'overlay_bubble.dart';
import 'screens/capture_screen.dart';
import 'dart:ui';

// Navigator key so we can navigate from outside widget tree (overlay listener)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayBubble()),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  

  /// Listen for overlay events
  FlutterOverlayWindow.overlayListener.listen((event) async {
    print("Overlay Event: $event");

    if (event == "bubble_clicked") {
      print("User clicked assistant bubble!");

      // Try to open the CaptureScreen using the navigatorKey.
      // If the app is in foreground and navigator is ready, this will push the screen.
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) =>
                const CaptureScreen(backendUrl: 'http://192.168.1.3:8000'),
          ),
        );
      } else {
        // App may be backgrounded or navigator not initialized yet.
        // Optionally log or handle bringing app to foreground in native code.
        print('Navigator not ready — cannot open CaptureScreen right now.');
      }
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Assistant',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // <<-- register the navigator key here
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Assistant")),
      body: Center(
        child: ElevatedButton(
          /*onPressed: () async {
            // Permission
            if (!await FlutterOverlayWindow.isPermissionGranted()) {
              await FlutterOverlayWindow.requestPermission();
            }

            // Show overlay bubble
            await FlutterOverlayWindow.showOverlay(
              height: 90,
              width: 90,
              alignment: OverlayAlignment.centerRight,
              flag: OverlayFlag.defaultFlag,
              enableDrag: true,
              startPosition: const OverlayPosition(200, 200),
            );
          },
          child: const Text("Start Assistant"),*/
          onPressed: () async {
            print("BUTTON PRESSED!");

            if (!await FlutterOverlayWindow.isPermissionGranted()) {
              print("Requesting permission...");
              await FlutterOverlayWindow.requestPermission();
            }

            print("Showing overlay...");
            /*await FlutterOverlayWindow.showOverlay(
              height: 90,
              width: 90,
              alignment: OverlayAlignment.centerRight,
              flag: OverlayFlag.defaultFlag,
              enableDrag: true,
              startPosition: const OverlayPosition(200, 200),
            );*/
            await FlutterOverlayWindow.showOverlay(
              height: 150,
              width: 150,
              alignment: OverlayAlignment.centerRight,
              enableDrag: true,
              flag: OverlayFlag.defaultFlag,
              visibility: NotificationVisibility.visibilityPublic,
            );

            print("OVERLAY EXECUTED");
          },
          child: const Text("Start Assistant"),
        ),
      ),
    );
  }
}
