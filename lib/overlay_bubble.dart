import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayBubble extends StatelessWidget {
  const OverlayBubble({super.key});

  @override
  Widget build(BuildContext context) {
    // WRAP IN MATERIAL to ensure it draws correctly
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: GestureDetector(
        onTap: () {
          print("Bubble Tapped"); // Check your logs for this!
          FlutterOverlayWindow.shareData("bubble_clicked");
        },
        child: Container(
          height: 90,
          width: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue,
            // Add shadow so you can see it against white backgrounds
            boxShadow: [
              BoxShadow(color: Colors.black45, blurRadius: 8, spreadRadius: 2)
            ],
          ),
          child: const Icon(Icons.translate, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
