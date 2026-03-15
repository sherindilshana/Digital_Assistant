import 'dart:ui';
import 'dart:isolate';
import 'dart:async';
import 'package:digital_assistant/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});

  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  bool _isWindowMode = false;
  bool _isLoading = false;
  List<String> _resultLines = [];
  final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription? _subscription;
  Timer? _safetyTimer;

  String _bubbleState = 'IDLE';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data is String) {
        // 1. Existing Translation Listener
        if (data.startsWith("RESULT:")) {
          _safetyTimer?.cancel();
          final rawText = data.replaceFirst("RESULT:", "");
          if (mounted) {
            await FlutterOverlayWindow.resizeOverlay(340, 480, true);
            await Future.delayed(const Duration(milliseconds: 200));
            setState(() {
              _isLoading = false;
              _resultLines = rawText.split('\n');
              _isWindowMode = true;
              _bubbleState = 'IDLE';
            });
          }
        }
        // 2. Form Field Success Listener
        else if (data.startsWith("FORM_FIELDS_RESULT:")) {
          String formFieldsText = data.replaceFirst("FORM_FIELDS_RESULT:", "");
          _processFormFields(formFieldsText);
        }
        // 3. MULTI-FIELD AUTO-FILL SUCCESS LISTENER
        else if (data.startsWith("CAMERA_TEXT_READY:")) {
          setState(() {
            _bubbleState = 'PASTE';
            _isLoading = false;
          });
          _speak("വിവരങ്ങൾ തനിയെ പൂരിപ്പിച്ചു കഴിഞ്ഞു. പരിശോധിക്കുക.");
        }
        // 🛡️ NEW: THE SMART JUMP LISTENER (ADD THIS HERE)
        else if (data.startsWith("PROCESS_NEXT_FIELD:")) {
          String nextHint = data.replaceFirst("PROCESS_NEXT_FIELD:", "");
          
          // This automatically triggers the backend to see if the next field
          // needs a Microphone or a Camera and updates the bubble icon.
          _processFormFields(nextHint); 
        }
        // 4. Form Field Error Listener
        else if (data.startsWith("FORM_FIELDS_ERROR:")) {
          _speak("ക്ഷമിക്കണം, ഒരു തകരാറുണ്ടായി.");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _safetyTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _flutterTts.setLanguage("ml-IN");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
  }

  void _closeWindow() {
    _flutterTts.stop();
    setState(() {
      _isWindowMode = false;
      _resultLines.clear();
      _bubbleState = 'IDLE';
      _isLoading = false;
    });
    FlutterOverlayWindow.resizeOverlay(90, 90, true);
  }

  // =======================================================
  // --- THE SINGLE SMART BUBBLE LOGIC ---
  // =======================================================

  Future<void> _handleSmartTap() async {
    // 🛡️ MODIFIED: The PASTE icon now acts as a verification/undo button
    if (_bubbleState == 'PASTE') {
      _speak("എല്ലാം ശരിയാണോ? എന്തെങ്കിലും മാറ്റം വരുത്തണമെങ്കിൽ വീണ്ടും സ്കാൻ ചെയ്യാം.");
      setState(() {
        _bubbleState = 'IDLE'; 
        _isLoading = false;
      });
      return;
    }

    if (_bubbleState == 'VOICE') {
      _startVoiceInput();
      return;
    } else if (_bubbleState == 'CAMERA') {
      _startCameraScan();
      return;
    }

    setState(() => _isLoading = true);
    final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');

    if (mainAppPort != null) {
      mainAppPort.send("GetFormFields");
    } else {
      _speak("ആപ്പ് തുറക്കുക");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processFormFields(String formFieldsText) async {
    try {
      if (formFieldsText.isEmpty || !formFieldsText.contains('[FIELD]')) {
        final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
        mainAppPort?.send("StartScan");
        return;
      }

      final String currentField = formFieldsText.split('\n').first;
      final actionData = await ApiService.getFormAction(currentField);

      await _speak(actionData['malayalam_audio'] ?? "ദയവായി വിവരങ്ങൾ നൽകുക");

      setState(() {
        _bubbleState = actionData['action'] ?? 'IDLE';
        _isLoading = false;
      });
    } catch (e) {
      _speak("ക്ഷമിക്കണം, ഒരു തകരാറുണ്ടായി.");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startVoiceInput() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: 'ml_IN',
          onResult: (val) async {
            if (val.hasConfidenceRating && val.confidence > 0) {
              setState(() => _isListening = false);
              final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
              mainAppPort?.send("InjectText:${val.recognizedWords}");
              setState(() => _bubbleState = 'IDLE');
              _speak("വിവരങ്ങൾ നൽകി");
            }
          },
        );
      }
    }
  }

  Future<void> _startCameraScan() async {
    _speak("ക്യാമറ തുറക്കുന്നു. രേഖകൾ കാണിക്കുക.");
    final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
    if (mainAppPort != null) {
      mainAppPort.send("OPENCAMERA");
      setState(() {
        _bubbleState = 'IDLE';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isWindowMode) {
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
                          IconButton(icon: const Icon(Icons.volume_up, color: Colors.white), onPressed: () => _speak(fullTextToSpeak)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _closeWindow, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _resultLines.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_resultLines[index], style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: _handleSmartTap,
          child: _isLoading
              ? const CircularProgressIndicator(color: Color(0xFF6A11CB))
              : Container(
                  height: 90,
                  width: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _bubbleState == 'IDLE' ? Colors.white : Colors.orangeAccent,
                    border: Border.all(color: const Color(0xFF6A11CB), width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                  ),
                  child: _buildDynamicIcon(),
                ),
        ),
      ),
    );
  }

  Widget _buildDynamicIcon() {
    switch (_bubbleState) {
      case 'VOICE': return Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 35);
      case 'CAMERA': return const Icon(Icons.camera_alt, color: Colors.white, size: 35);
      case 'AUTO_WAIT': return const Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.white));
      case 'GUIDE_KEYBOARD': return const Icon(Icons.lock, color: Colors.white, size: 35);
      case 'PASTE': return const Icon(Icons.assignment_turned_in, color: Colors.white, size: 35);
      default: return Padding(padding: const EdgeInsets.all(12.0), child: Image.asset('assets/images/logo.png'));
    }
  }
}