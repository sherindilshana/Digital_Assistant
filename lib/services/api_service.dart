import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ CRITICAL: Replace this with your LAPTOP'S IP from 'ipconfig'
  // Do NOT use localhost. Use 192.168.x.x
  static const String _baseUrl = "http://127.0.0.1:8000/api/translate/";

  // --- NEW: FORM ASSISTANT URL ---
  static const String _formAssistUrl = "http://127.0.0.1:8000/api/form-assist/";

  // --- TRANSLATION FEATURE ---
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

  // --- NEW: FORM ASSISTANT API CALL ---
  static Future<Map<String, dynamic>> getFormAction(String fieldHint) async {
    try {
      print("ApiService: Requesting Form Action from $_formAssistUrl");
      final response = await http
          .post(
            Uri.parse(_formAssistUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"field_hint": fieldHint}),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw "Timeout: Laptop not reachable.";
            },
          );

      if (response.statusCode == 200) {
        // Returns the JSON dictionary: { "action": "...", "malayalam_audio": "..." }
        return jsonDecode(response.body);
      } else {
        print('Server Error: ${response.statusCode}');
        // Safe fallback if the server throws an error
        return {
          "action": "VOICE",
          "malayalam_audio": "സർവർ തകരാറിലാണ്. ദയവായി വിവരങ്ങൾ പറയുക.",
        };
      }
    } catch (e) {
      print('Network Error: $e');
      // Safe fallback if the internet disconnects
      return {
        "action": "VOICE",
        "malayalam_audio": "ഇന്റർനെറ്റ് ലഭ്യമല്ല. ദയവായി വിവരങ്ങൾ പറയുക.",
      };
    }
  }

  static Future<Map<String, dynamic>> getUniversalScanData(
    String rawText,
  ) async {
    final response = await http.post(
      Uri.parse("http://127.0.0.1:8000/api/universal-scan/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"raw_text": rawText}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data_map'];
    }
    return {};
  }
}
