import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ CRITICAL: Replace this with your LAPTOP'S IP from 'ipconfig'
  // Do NOT use localhost. Use 192.168.x.x
  static const String _baseUrl = "http://192.168.1.2:8000/api/translate/";
  static Future<String> sendToBackend(String text) async {
    try {
      print("ApiService: Sending to $_baseUrl");
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"text": text}),
          )
          .timeout(
            const Duration(seconds: 50), // Fail fast if laptop is off
            onTimeout: () {
              throw "Timeout: Laptop not reachable.";
            },
          );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // We return the Translated Text + The Source (Online/Offline)
        //return "${data['translated']}\n\n(Source: ${data['source']})";
        String translated = data['translated'] ?? "";

        // Remove bold markdown
        translated = translated.replaceAll("**", "");

        // Replace bullet stars with dash so structure remains
        translated = translated.replaceAll(
          RegExp(r'^\*\s?', multiLine: true),
          "- ",
        );

        // Clean spaces
        translated = translated.trim();

        return translated;
      } else {
        return "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      print("ApiService Error: $e");
      return "Connection Failed.\nMake sure Phone & Laptop are on same Wi-Fi.";
    }
  }
}
