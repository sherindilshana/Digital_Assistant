import 'dart:ui';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_tts/flutter_tts.dart'; // <--- 1. NEW IMPORT

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});

  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  // --- STATE VARIABLES ---
  bool _isWindowMode = false; // False = Bubble, True = Window
  bool _isLoading = false;
  List<String> _resultLines = [];
  
  // --- NEW: TTS ENGINE ---
  final FlutterTts _flutterTts = FlutterTts(); // <--- 2. TTS ENGINE
  
  StreamSubscription? _subscription;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    // Listen for data from the Main App
    _subscription = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data is String && data.startsWith("RESULT:")) {
        _safetyTimer?.cancel();
        final rawText = data.replaceFirst("RESULT:", "");
        
        if (mounted) {
          await FlutterOverlayWindow.resizeOverlay(340, 480, true);
          await Future.delayed(const Duration(milliseconds: 200));

          setState(() {
            _isLoading = false;
            
            // Process text safely
            List<String> lines = rawText.split('\n');
            if (lines.length > 100) {
              lines = lines.sublist(0, 100);
              lines.add("... (List truncated for safety)");
            }
            _resultLines = lines;
            _isWindowMode = true; // Switch UI mode
          });
          
          // Optional: Auto-speak when window opens (Uncomment if needed)
          // _speak(rawText);
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _safetyTimer?.cancel();
    _flutterTts.stop(); // <--- 3. CLEANUP VOICE
    super.dispose();
  }

  // --- NEW: SPEAK FUNCTION ---
  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    
    // Configure Voice settings for Elderly
    await _flutterTts.setLanguage("ml-IN"); // Malayalam
    await _flutterTts.setSpeechRate(0.4);   // Slower speed
    await _flutterTts.setPitch(1.0);
    
    await _flutterTts.speak(text);
  }

  Future<void> _handleTap() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
    if (mainAppPort != null) {
      mainAppPort.send("StartScan");
      
      _safetyTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _isLoading) {
          _showError("Timeout. Service might be OFF.\nGo to Settings -> Accessibility.");
        }
      });
    } else {
      _showError("Error: Main App disconnected. Open App to reconnect.");
    }
  }

  Future<void> _showError(String message) async {
    await FlutterOverlayWindow.resizeOverlay(340, 480, true);
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _resultLines = [message];
        _isWindowMode = true;
      });
    }
  }

  void _closeWindow() {
    _flutterTts.stop(); // Stop speaking if closed
    setState(() {
      _isWindowMode = false;
      _resultLines.clear();
    });
    FlutterOverlayWindow.resizeOverlay(90, 90, true);
  }

  @override
  Widget build(BuildContext context) {
    // -----------------------------------------------------------
    // MODE 1: THE RESULT WINDOW
    // -----------------------------------------------------------
    if (_isWindowMode) {
      // Helper: Join lines back into one string for speaking
      String fullTextToSpeak = _resultLines.join(" ");

      return Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 320, 
            height: 460, 
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6A11CB), width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6A11CB),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Screen Content", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                           // --- 4. NEW: SPEAKER ICON IN HEADER ---
                          IconButton(
                            icon: const Icon(Icons.volume_up, color: Colors.white),
                            onPressed: () => _speak(fullTextToSpeak),
                            tooltip: "Read Aloud",
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: _closeWindow,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Safe List
                Expanded(
                  child: _resultLines.isEmpty
                      ? const Center(child: Text("No text found on screen."))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _resultLines.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _resultLines[index],
                                style: const TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            );
                          },
                        ),
                ),
                
                // Optional: Bottom Speaker Button (Alternative Placement)
                // If you prefer a big button at the bottom, uncomment this:
                /*
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text("Listen"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A11CB),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _speak(fullTextToSpeak),
                  ),
                ),
                */
              ],
            ),
          ),
        ),
      );
    }

    // -----------------------------------------------------------
    // MODE 2: THE FLOATING BUBBLE
    // -----------------------------------------------------------
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: _handleTap,
          child: _isLoading
              ? const CircularProgressIndicator(color: Color(0xFF6A11CB))
              : Container(
                  height: 90,
                  width: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.translate, color: Colors.white, size: 40),
                ),
        ),
      ),
    );
  }
}