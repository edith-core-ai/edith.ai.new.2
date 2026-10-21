import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'gemini_endpoints.dart';
import 'settings_service.dart';

/// Makes pictures from a text description. Gemini's image model first,
/// then Grok's if a Grok key is set. Pictures are saved on the phone.
class ImageGenService {
  static const String geminiImageModel = 'gemini-2.5-flash-image';
  static const String grokImageModel = 'grok-imagine-image-2.0';

  /// Why the last try failed (for the reply to Hilal).
  static String lastError = '';

  /// Returns the saved file path, or null.
  Future<String?> generate(String prompt) async {
    lastError = '';
    if (SettingsService.hasGeminiKey) {
      final bytes = await _gemini(prompt);
      if (bytes != null) return _save(bytes);
    }
    if (SettingsService.hasGrokKey) {
      final bytes = await _grok(prompt);
      if (bytes != null) return _save(bytes);
    }
    if (lastError.isEmpty) lastError = 'No Gemini or Grok key is set.';
    return null;
  }

  Future<List<int>?> _gemini(String prompt) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE']
      },
    });
    final keys = <String>{
      for (final a in GeminiEndpoints.attempts()) a.key,
    };
    for (final key in keys) {
      try {
        final res = await http
            .post(
              GeminiEndpoints.url(geminiImageModel),
              headers: GeminiEndpoints.headers(key),
              body: body,
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) {
          lastError = 'Gemini image error ${res.statusCode}';
          continue;
        }
        final parts = jsonDecode(res.body)['candidates']?[0]?['content']
            ?['parts'] as List<dynamic>?;
        final data = parts?.firstWhere(
          (p) => p['inlineData'] != null,
          orElse: () => null,
        )?['inlineData']?['data'] as String?;
        if (data != null) return base64Decode(data);
        lastError = 'Gemini returned no picture';
      } catch (e) {
        lastError = 'Gemini image failed: $e';
      }
    }
    return null;
  }

  Future<List<int>?> _grok(String prompt) async {
    try {
      final res = await http
          .post(
            Uri.parse('https://api.x.ai/v1/images/generations'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${SettingsService.grokApiKey}',
            },
            body: jsonEncode({
              'model': grokImageModel,
              'prompt': prompt,
              'response_format': 'b64_json',
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        lastError = '$lastError; Grok image error ${res.statusCode}'.trim();
        return null;
      }
      final b64 = jsonDecode(res.body)['data']?[0]?['b64_json'] as String?;
      return b64 == null ? null : base64Decode(b64);
    } catch (e) {
      lastError = '$lastError; Grok image failed: $e'.trim();
      return null;
    }
  }

  Future<String> _save(List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/edith_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file =
        File('${folder.path}/gen_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
