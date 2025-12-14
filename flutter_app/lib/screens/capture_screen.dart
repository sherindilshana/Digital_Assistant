// flutter_app/lib/screens/capture_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_app/ocr_apload.dart';

class CaptureScreen extends StatefulWidget {
  final String backendUrl;
  const CaptureScreen({required this.backendUrl, Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  String _result = 'No OCR yet';
  bool _loading = false;

  Future<void> _pickAndUpload() async {
    setState(() { _loading = true; });
    final uploader = OcrUploader(widget.backendUrl);
    final picked = await uploader.pickImage();
    if (picked == null) {
      setState(() { _loading = false; _result = 'No image selected'; });
      return;
    }
    final res = await uploader.uploadForOcr(picked);
    setState(() {
      _loading = false;
      if (res == null) _result = 'Upload failed';
      else {
        try {
          final json = jsonDecode(res);
          _result = json['text'] ?? 'no text';
        } catch (e) {
          _result = res;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Optionally auto-run picker on open:
    // WidgetsBinding.instance.addPostFrameCallback((_) => _pickAndUpload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture / OCR')),
      body: Center(
        child: _loading
          ? const CircularProgressIndicator()
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(onPressed: _pickAndUpload, child: const Text('Pick screenshot and run OCR')),
                  const SizedBox(height: 20),
                  const Text('OCR result:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_result, textAlign: TextAlign.center),
                ],
              ),
            ),
      ),
    );
  }
}
