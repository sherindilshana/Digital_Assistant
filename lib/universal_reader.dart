import 'package:flutter/material.dart';
import 'services/tts_service.dart';

class UniversalReaderPage extends StatefulWidget {
  final String rawText;
  const UniversalReaderPage({super.key, required this.rawText});

  @override
  State<UniversalReaderPage> createState() => _UniversalReaderPageState();
}

class _UniversalReaderPageState extends State<UniversalReaderPage> {
  final TtsService _tts = TtsService();
  List<String> _displayItems = [];
  //bool _isNoticeMode = false;
  String _documentTitle = "സ്കാൻ ചെയ്ത രേഖ";

  @override
  void initState() {
    super.initState();
    _processSmartContent();
  }

  void _processSmartContent() {
    // DEBUG: show raw OCR output in terminal
    print("OCR TEXT:");
    print(widget.rawText);

    String text =
        widget.rawText
            .replaceAll(RegExp(r'\b[OD]\b'), '')
            .replaceAll('*', '')
            .replaceAll('_', '')
            .trim();

    //text = text.replaceAll(RegExp(r'\s+'), ' ');

    // Move form title (like "Registration Form") to top if OCR captured it later
    List<String> lines = text.split('\n').map((l) => l.trim()).toList();

    // Remove website/footer noise
    lines.removeWhere((l) => l.toLowerCase().contains(".com"));

    int titleIndex = lines.indexWhere(
      (l) => RegExp(r'form', caseSensitive: false).hasMatch(l),
    );
    if (titleIndex > 0) {
      String title = lines.removeAt(titleIndex);
      lines.insert(0, title);
    }

    text = lines.join('\n');

    _documentTitle = _detectDocumentType(text);
    // 1. SMART DETECTION
    // Forms usually have colons (:) or many short labels.
    // Notices usually have long sentences without colons.
    int colonCount = RegExp(r':').allMatches(text).length;
    bool looksLikeForm = colonCount > 1 || text.contains("____");

    setState(() {
      if (!looksLikeForm) {
        // --- NOTICE MODE ---
        //_isNoticeMode = true;

        // Clean the text first
        String cleanText = text.replaceAll(RegExp(r'\s+'), ' ').trim();

        // Break the paragraph into meaningful sentences
        List<String> sentences =
            cleanText
                .split(RegExp(r'[.!?]'))
                .map((s) => s.trim())
                .where((s) => s.length > 10)
                .toList();

        // Keep sentences short and meaningful
        _displayItems =
            sentences.map((s) {
              if (s.length > 120) {
                return "${s.substring(0, 120)}...";
              }
              return s;
            }).toList();
      } else {
        // --- FORM MODE ---
        //_isNoticeMode = false;

        // Split OCR text by lines and remove empty lines
        List<String> rawLines =
            text
                .split(RegExp(r'[\n\r]+'))
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();

        // Each line becomes its own card (simple and reliable for OCR)
        _displayItems = rawLines;

        // Fallback in case OCR gives one long block
        if (_displayItems.isEmpty) {
          _displayItems = [text];
        }
      }
    });

    _tts.speak(
      "സ്കാൻ ചെയ്ത എഴുത്ത് മലയാളത്തിലേക്ക് മാറ്റിയിട്ടുണ്ട്. ഓരോ കാർഡിലുമുള്ള ശബ്ദ ചിഹ്നത്തിൽ അമർത്തിയാൽ ഞാൻ അത് വായിച്ചുതരാം.",
    );
  }

  String _detectDocumentType(String text) {
    final t = text.toLowerCase();

    if (t.contains("form") ||
        t.contains("application") ||
        t.contains("registration") ||
        t.contains("അപേക്ഷ")) {
      return "ഫോം (Form)";
    }

    if (t.contains("notice") ||
        t.contains("announcement") ||
        t.contains("അറിയിപ്പ്")) {
      return "അറിയിപ്പ് (Notice)";
    }

    if (t.contains("government") ||
        t.contains("ministry") ||
        t.contains("kerala") ||
        t.contains("സർക്കാർ")) {
      return "സർക്കാർ രേഖ (Government Document)";
    }

    return "സ്കാൻ ചെയ്ത രേഖ (Scanned Document)";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_documentTitle),
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: ExcludeSemantics(
        // Essential to stop the crash loop
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20), //
          itemCount: _displayItems.length,
          itemBuilder: (context, index) {
            return Card(
              elevation: 5,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: InkWell(
                onTap: () => _tts.speak(_displayItems[index]),
                borderRadius: BorderRadius.circular(15),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.volume_up,
                        size: 26,
                        color: const Color(0xFF6A11CB),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _displayItems[index],
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


