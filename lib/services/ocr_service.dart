import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static Future<String> processImage(String imagePath) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      // Process the Image
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      return recognizedText.text;
      
    } catch (e) {
      return "Error processing image: $e";
    } finally {
      // SAFETY FIX: This ensures the recognizer runs 'close()' 
      // even if the app crashes during scanning.
      await textRecognizer.close();
    }
  }
}
