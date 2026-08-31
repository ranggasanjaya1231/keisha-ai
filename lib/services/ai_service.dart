import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AIService {
  static Future<String> callMercuryApi(List<Map<String, String>> chatHistory) async {
    final apiKey = dotenv.env['MERCURY_API_KEY'] ?? '';
    final url = Uri.parse('https://api.inceptionlabs.ai/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
      body: jsonEncode({"model": "mercury-2", "messages": chatHistory, "temperature": 0.7}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['choices'][0]['message']['content'] ?? '';
    } else {
      throw Exception('Error Mercury API: ${response.statusCode}');
    }
  }
}
