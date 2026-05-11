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
        // 🛡️ CRITICAL: Always reset loading as soon as ANY message arrives
        if (mounted) setState(() => _isLoading = false);
        // 1. Existing Translation Listener (UNCHANGED)
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
          // 🛡️ Cancel the safety timer - response arrived, system is working fine
          _safetyTimer?.cancel();
          String formFieldsText = data.replaceFirst("FORM_FIELDS_RESULT:", "");
          _processFormFields(formFieldsText);
        }
        // 3. MULTI-FIELD AUTO-FILL SUCCESS LISTENER
        else if (data.startsWith("CAMERA_TEXT_READY:")) {
          setState(() => _bubbleState = 'PASTE');
          _speak("വിവരങ്ങൾ തനിയെ പൂരിച്ചു. ഒന്ന് പരിശോധിക്കൂ.");
        }
        // 🛡️ SMART JUMP LISTENER: auto-move to next field after camera scan
        else if (data.startsWith("PROCESS_NEXT_FIELD:")) {
          _safetyTimer?.cancel(); // Cancel timer - operation succeeded
          String nextHint = data.replaceFirst("PROCESS_NEXT_FIELD:", "");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
          _processFormFields(nextHint);
        }
        // 4. OTP auto-filled by Kotlin notification listener
        else if (data.startsWith("OTP_FILLED:")) {
          _speak("OTP സ്വയം പൂരിപ്പിച്ചു.");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
        }
        // 5. Email was picked from OS picker
        else if (data.startsWith("EMAIL_FILLED:")) {
          _speak("ഇമെയിൽ ചേർത്തു.");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
        }
        // 6. Form Field Error Listener
        else if (data.startsWith("FORM_FIELDS_ERROR:")) {
          _speak("ക്ഷമിക്കണം, ഒരു തകരാറുണ്ടായി.");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
        }
        // 7. Form Complete — all fields are filled!
        else if (data.startsWith("FORM_COMPLETE:")) {
          _speak("ഫോമിൽ കാണുന്ന വിവരങ്ങൾ പൂർണ്ണമായി. താഴേക്ക് നീക്കാൻ ഉണ്ടെങ്കിൽ, നീക്കിയ ശേഷം വീണ്ടും ബട്ടൺ അമർത്തുക.");
          setState(() {
            _bubbleState = 'IDLE';
            _isLoading = false;
          });
        }
        // 8. General TTS commands
        else if (data.startsWith("TTS:")) {
          _speak(data.substring(4));
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
    // Non-IDLE states handle their own tap action first — never show spinner for these
    if (_bubbleState == 'VOICE') {
      _startVoiceInput();
      return;
    } else if (_bubbleState == 'CAMERA') {
      _startCameraScan();
      return;
    } else if (_bubbleState == 'PASTE') {
      _speak("വിവരങ്ങൾ ശരിയായോ എന്ന് പരിശോധിക്കുക.");
      setState(() {
        _bubbleState = 'IDLE';
        _isLoading = false;
      });
      return;
    } else if (_bubbleState == 'EMAIL_POPUP') {
      // Tell main app to open the OS native account picker
      _speak("ഇമെയിൽ അക്കൗണ്ട് തിരഞ്ഞെടുക്കൂ.");
      final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
      mainAppPort?.send("TRIGGER_EMAIL_POPUP");
      setState(() {
        _bubbleState = 'IDLE';
        _isLoading = false;
      });
      return;
    } else if (_bubbleState == 'AUTO_WAIT') {
      // OTP mode: already waiting, just remind the user
      _speak("OTP വരുന്നത് കാത്തിരിക്കുന്നു. ഞാൻ തനിയെ പൂരിപ്പിക്കാം.");
      return;
    } else if (_bubbleState == 'GUIDE_KEYBOARD' || _bubbleState == 'PASSWORD_PROMPT') {
      // Repeat prompt safely if they tap the background
      _speak("പാസ്‌വേഡ് അറിയാമെങ്കിൽ 'അതെ' എന്ന് അമർത്തുക. അറിയില്ലെങ്കിൽ 'ഇല്ല' എന്ന് അമർത്തുക.");
      return;
    }

    // IDLE tap — ask for form fields (or translation if not on a form)
    setState(() => _isLoading = true);
    _safetyTimer?.cancel();
    // Silent safety net: only resets spinner if truly stuck
    _safetyTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _isLoading = false);
    });
    final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
    if (mainAppPort != null) {
      mainAppPort.send("GetFormFields");
    } else {
      _safetyTimer?.cancel();
      _speak("ആപ്പ് ഒന്ന് തുറക്കൂ.");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processFormFields(String formFieldsText) async {
    try {
      // Ensure spinner is off before calling backend
      if (mounted) setState(() => _isLoading = false);
      if (formFieldsText.isEmpty ||
          (!formFieldsText.contains('[FIELD]') && !formFieldsText.contains('[PASSWORD]'))) {
        // Fallback: If no field is focused, do a normal screen scan
        final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
        mainAppPort?.send("StartScan");
        return;
      }

      final String currentField = formFieldsText.split('\n').first;

      // 🛡️ PASSWORD SHORTCUT: Go directly to PASSWORD_PROMPT — no backend call needed
      if (currentField.startsWith('[PASSWORD]')) {
        _speak(
          "പാസ്‌വേഡ് സേവ് ചെയ്തിട്ടില്ലെങ്കിൽ, താങ്കൾക്ക് അറിയാമെങ്കിൽ 'അതെ' എന്ന് അമർത്തുക. അറിയില്ലെങ്കിൽ 'ഇല്ല' എന്ന് അമർത്തുക.",
        );
        if (mounted) {
          setState(() {
            _bubbleState = 'PASSWORD_PROMPT';
            _isLoading = false;
          });
        }
        FlutterOverlayWindow.resizeOverlay(250, 90, true);
        return;
      }

      // Call backend to decide: CAMERA, VOICE, EMAIL_POPUP, etc.
      final actionData = await ApiService.getFormAction(currentField);
      _speak(actionData['malayalam_audio'] ?? "വിവരങ്ങൾ നൽകുക");

      final String action = actionData['action'] ?? 'IDLE';

      // 🛡️ OTP: immediately start watching for SMS on Kotlin side
      if (action == 'AUTO_WAIT') {
        final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
        mainAppPort?.send("START_OTP_WATCH");
      }

      if (mounted) {
        setState(() {
          _bubbleState = action;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _speak("ക്ഷമിക്കണം, തകരാറുണ്ടായി.");

    }
  }

  Future<void> _startVoiceInput() async {
    // 🛡️ FIX: If mic is already listening and user taps again → STOP and reset
    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _bubbleState = 'IDLE';
      });
      _speak("ശ്രവണം നിർത്തി.");
      return;
    }

    bool available = await _speech.initialize(
      onError: (error) {
        // Auto-reset on any speech error
        if (mounted) {
          setState(() {
            _isListening = false;
            _bubbleState = 'IDLE';
          });
        }
      },
    );

    if (available) {
      setState(() {
        _isListening = true;
        _isLoading = false;
      });

      // Auto-timeout: silently resets mic if no speech within 15 seconds
      _safetyTimer?.cancel();
      _safetyTimer = Timer(const Duration(seconds: 15), () {
        if (_isListening) {
          _speech.stop();
          if (mounted) {
            setState(() {
              _isListening = false;
              _bubbleState = 'IDLE';
            });
          }
          // Silent reset — no TTS so we don't interrupt the user
        }
      });

      _speech.listen(
        localeId: 'ml_IN',
        onResult: (val) async {
          // Accept any words, not just high-confidence results
          if (val.recognizedWords.isNotEmpty && val.finalResult) {
            _safetyTimer?.cancel();
            await _speech.stop();
            setState(() {
              _isListening = false;
              _isLoading = true; // Show spinner while formatting
            });
            
            // Format Malayalam audio into English text via backend
            String formattedText = await ApiService.formatVoiceInput(val.recognizedWords);

            final SendPort? mainAppPort =
                IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
            mainAppPort?.send("InjectText:$formattedText");
            
            setState(() {
              _bubbleState = 'IDLE';
              _isLoading = false;
            });
            _speak("വിവരങ്ങൾ നൽകി.");
          }
        },
      );
    } else {
      _speak("മൈക്ക് ലഭ്യമല്ല.");
      setState(() => _bubbleState = 'IDLE');
    }
  }

  Future<void> _startCameraScan() async {
    _speak("ക്യാമറ തുറക്കുന്നു. രേഖകൾ കാണിക്കുക.");
    final SendPort? mainAppPort = IsolateNameServer.lookupPortByName(
      'ASSISTANT_PORT',
    );
    if (mainAppPort != null) {
      mainAppPort.send("OPENCAMERA");
      setState(() {
        _bubbleState = 'IDLE';
        _isLoading = false;
      });
    }
  }

  // --- UI RENDER (EXACTLY AS YOU HAD IT) ---
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
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6A11CB),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Screen Content",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.volume_up,
                              color: Colors.white,
                            ),
                            onPressed: () => _speak(fullTextToSpeak),
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
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _resultLines.length,
                    itemBuilder:
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _resultLines[index],
                            style: const TextStyle(fontSize: 14),
                          ),
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
        child: _bubbleState == 'PASSWORD_PROMPT'
          ? Container(
              height: 70,
              width: 230,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(35),
                border: Border.all(color: const Color(0xFF6A11CB), width: 2),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      FlutterOverlayWindow.resizeOverlay(90, 90, true);
                      setState(() => _bubbleState = 'IDLE');
                      _startVoiceInput();
                    },
                    icon: const Icon(Icons.mic, color: Colors.green, size: 24),
                    label: const Text("അതെ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  Container(width: 1, color: Colors.grey.shade300, height: 40),
                  TextButton.icon(
                    onPressed: () {
                      FlutterOverlayWindow.resizeOverlay(90, 90, true);
                      setState(() => _bubbleState = 'IDLE');
                      final SendPort? mainAppPort = IsolateNameServer.lookupPortByName('ASSISTANT_PORT');
                      mainAppPort?.send("CLICK_FORGOT_PASSWORD");
                    },
                    icon: const Icon(Icons.touch_app, color: Colors.red, size: 24),
                    label: const Text("ഇല്ല", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
              ),
            )
          : GestureDetector(
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
      case 'VOICE':
        return Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: Colors.white,
          size: 35,
        );
      case 'CAMERA':
        return const Icon(Icons.camera_alt, color: Colors.white, size: 35);
      case 'EMAIL_POPUP':
        return const Icon(Icons.email_rounded, color: Colors.white, size: 35);
      case 'AUTO_WAIT':
        // Spinner already shown via _isLoading when action is dispatched.
        // This icon shows if bubble re-renders in this state.
        return const Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        );
      case 'GUIDE_KEYBOARD':
        return const Icon(Icons.lock_rounded, color: Colors.white, size: 35);
      case 'PASTE':
        return const Icon(
          Icons.assignment_turned_in,
          color: Colors.white,
          size: 35,
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Image.asset('assets/images/logo.png'),
        );
    }
  }
}
