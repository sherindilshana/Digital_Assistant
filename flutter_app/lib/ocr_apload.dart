// flutter_app/lib/ocr_upload.dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class OcrUploader {
  final String backendBaseUrl; // e.g. "http://10.0.2.2:8000" for Android emulator

  OcrUploader(this.backendBaseUrl);

  /// Opens gallery to pick an image (returns null if none picked)
  Future<XFile?> pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    return picked;
  }

  /// Uploads the picked image to backend /ocr endpoint and returns response body
  Future<String?> uploadForOcr(XFile imageFile) async {
    final uri = Uri.parse('$backendBaseUrl/ocr');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      return res.body; // expected JSON like {"text":"..."}
    } else {
      print('Upload failed: ${res.statusCode} ${res.body}');
      return null;
    }
  }
}
