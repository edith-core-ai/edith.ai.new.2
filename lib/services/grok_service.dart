import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

/// Plain Grok (xAI) chat, no tools. Used as the backup brain for the
/// builder, vision and other one-shot requests when Gemini fails.
class GrokService {
  GrokService._();

  static bool get available => SettingsService.hasGrokKey;

  static Future<String> chat(String system, String user) async {
    final res = await http
        .post(
          Uri.parse('https://api.x.ai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${SettingsService.grokApiKey}',
          },
          body: jsonEncode({
            'model': SettingsService.grokModel,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('Grok failed (${res.statusCode}): ${res.body}');
    }
    final msg = jsonDecode(res.body)['choices']?[0]?['message'];
    return (msg?['content'] ?? '').toString();
  }
}
