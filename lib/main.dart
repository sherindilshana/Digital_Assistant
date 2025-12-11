import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'overlay_bubble.dart';

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

  /// Listen for overlay events
  FlutterOverlayWindow.overlayListener.listen((event) async {
    print("Overlay Event: $event");

    if (event == "bubble_clicked") {
      print("User clicked assistant bubble!");

      // TODO: CAPTURE SCREEN + RUN OCR HERE
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
          onPressed: () async {
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
          child: const Text("Start Assistant"),
        ),
      ),
    );
  }
}
