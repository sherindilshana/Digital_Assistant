import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false; // Track initialization status

  // Constructor doesn't force init immediately, logic moves to speak
  TtsService();

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("ml-IN");
      
      // 2. Adjust Speed & Pitch
      await _flutterTts.setSpeechRate(0.4); 
      await _flutterTts.setPitch(1.0);
      
      // 3. Wait for completion (Optional but good for Android)
      await _flutterTts.awaitSpeakCompletion(true);

      _isInitialized = true;
    } catch (e) {
      print("TTS Init Error: $e");
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    // ✨ SAFETY CHECK: Initialize if not done yet
    if (!_isInitialized) {
      await _initTts();
    }

    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}