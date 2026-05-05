import 'dart:convert';
import 'package:http/http.dart' as http;

class SourceReliabilityService {
  static String? lastVerifiedSource;
  static String? lastVerifiedApp;

  // -------------------------------
  // 1️⃣ Trusted Domains
  // -------------------------------
  static final List<String> trustedDomains = [
    "gov.in",
    "nic.in",
    "kerala.gov.in",
    "who.int",
    "unicef.org",
    "rbi.org.in",
  ];
  // -------------------------------
  //  Scam keyword detection
  // -------------------------------
  static final List<String> scamKeywords = [
    "you won",
    "lottery",
    "claim now",
    "urgent",
    "limited offer",
    "click here",
    "congratulations",
    "free money",
    "reward",
    "offer expires",
  ];
  static final List<String> suspiciousDomains = [
    ".xyz",
    ".loan",
    ".click",
    ".top",
    ".win",
  ];

  // -------------------------------
  // Extract URL from text
  // -------------------------------
  static List<String> extractUrls(String text) {
    final regex = RegExp(
      r'((https?:\/\/)?([\w\-]+\.)+[a-z]{2,}(\/\S*)?)',
      caseSensitive: false,
    );

    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  // -------------------------------
  // Detect scam messages without URL
  // -------------------------------
  static String checkScamText(String text) {
    String lower = text.toLowerCase();

    for (String word in scamKeywords) {
      if (lower.contains(word)) {
        return "⚠ Suspicious Message\nPossible scam content detected";
      }
    }

    return "CLEAR";
  }

  // -------------------------------
  // 1️⃣ DOMAIN WHITELIST CHECK
  // -------------------------------
  static String checkWhitelist(String url) {
    for (String domain in trustedDomains) {
      if (url.contains(domain)) {
        return "🟢 Trusted Source\n$url";
      }
    }

    return "UNKNOWN";
  }

  // -------------------------------
  // 2️⃣ GOOGLE SAFE BROWSING CHECK
  // -------------------------------
  static Future<String> checkGoogleSafety(String url) async {
    const apiKey = "AIzaSyCWjlHWvWd8n69yNnq0zbG1REyYT6FedsE";

    final body = {
      "client": {"clientId": "digital_assistant", "clientVersion": "1.0"},
      "threatInfo": {
        "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING"],
        "platformTypes": ["ANY_PLATFORM"],
        "threatEntryTypes": ["URL"],
        "threatEntries": [
          {"url": url},
        ],
      },
    };

    final response = await http.post(
      Uri.parse(
        "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$apiKey",
      ),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data.containsKey("matches")) {
        return "🔴 Unsafe Website\n$url";
      } else {
        return "🟡 Unknown Source\n$url";
      }
    }

    return "⚠ Could not verify source";
  }

  // -------------------------------
  // FINAL CHECK FUNCTION
  // -------------------------------
  static Future<String> checkSource(String text, String currentApp) async {
    List<String> urls = extractUrls(text);

    if (urls.isNotEmpty) {
      String url = urls.first.toLowerCase();

      String whitelistResult = checkWhitelist(url);

      if (whitelistResult != "UNKNOWN") {
        lastVerifiedSource = url;
        lastVerifiedApp = currentApp;

        return "🟢 Trusted Source\n$url";
      }
      // -------------------------------
      // Suspicious Domain Check
      // -------------------------------
      for (String s in suspiciousDomains) {
        if (url.contains(s)) {
          return "🔴 Suspicious Website\n$url";
        }
      }
      // Google Safe Browsing check
      String result = await checkGoogleSafety(url);

      if (result.contains("Unsafe")) {
        lastVerifiedSource = null;
        lastVerifiedApp = null;
      }

      return result;
    }

    // Only reuse trusted source if same app
    if (lastVerifiedSource != null && lastVerifiedApp == currentApp) {
      return "🟢 Trusted Source\n$lastVerifiedSource";
    }

    // No URL found → check scam text
    String scamCheck = checkScamText(text);

    if (scamCheck != "CLEAR") {
      return scamCheck;
    }

    return "ℹ No source detected";
  }
}