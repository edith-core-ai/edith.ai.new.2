import 'dart:convert';
import '../brains/edith_persona.dart';
import '../models/message.dart';
import 'gemini_endpoints.dart';
import 'grok_service.dart';

/// Conversation Brain — v0.1
///
/// Plain (non-streaming) Gemini calls: text with Google Search grounding,
/// and image questions (vision). Model, keys and fallback all live in
/// [GeminiEndpoints].
class GeminiService {
  /// Gemini first. If it fails and a Grok key is set, Grok answers.
  Future<String> ask(String userInput, List<Message> history) async {
    try {
      return await _askGemini(userInput, history);
    } catch (e) {
      if (!GrokService.available) rethrow;
      return GrokService.chat(edithSystemPrompt, userInput);
    }
  }

  Future<String> _askGemini(String userInput, List<Message> history) async {
    // Build conversation contents: persona goes in systemInstruction,
    // history + new input go in contents.
    final contents = [
      ...history.where((m) => m.content.isNotEmpty).map((m) => {
            'role': m.role == 'user' ? 'user' : 'model',
            'parts': [
              {'text': m.content}
            ],
          }),
      {
        'role': 'user',
        'parts': [
          {'text': userInput}
        ],
      },
    ];

    // Give EDITH real awareness of "now" — without this, she has no idea
    // what today's date is and will either guess or dodge the question.
    final now = DateTime.now();
    final dateContext =
        'Current date and time: ${now.toIso8601String()} (device local time).';

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': '$edithSystemPrompt\n\n$dateContext'}
        ]
      },
      'contents': contents,
      // Grounding with Google Search — lets EDITH check the live web
      // instead of guessing from stale training data. Google Search
      // can't be mixed with function-calling tools in one request.
      'tools': [
        {'google_search': {}}
      ],
    });

    final response = await GeminiEndpoints.post(body);

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini request failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    try {
      final parts =
          data['candidates'][0]['content']['parts'] as List<dynamic>;
      return parts
          .where((p) => p['thought'] != true)
          .map((p) => p['text'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .join('\n');
    } catch (_) {
      return "Something's off on my end, Boss — got a response I couldn't parse.";
    }
  }

  /// Vision — v0.3. Sends an image alongside a text prompt so EDITH can
  /// describe, read, or analyze whatever the camera/gallery picked up.
  Future<String> askWithImage(
    String userInput,
    List<int> imageBytes,
    String mimeType,
  ) async {
    final now = DateTime.now();
    final dateContext =
        'Current date and time: ${now.toIso8601String()} (device local time).';

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': '$edithSystemPrompt\n\n$dateContext'}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userInput.isEmpty ? 'What do you see here?' : userInput},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Encode(imageBytes),
              }
            },
          ],
        },
      ],
      // google_search grounding can't be combined with image input in the
      // same request, so vision requests skip live search.
    });

    final response = await GeminiEndpoints.post(body);

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini vision request failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    try {
      final parts =
          data['candidates'][0]['content']['parts'] as List<dynamic>;
      return parts
          .where((p) => p['thought'] != true)
          .map((p) => p['text'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .join('\n');
    } catch (_) {
      return "Couldn't make sense of that image, Boss.";
    }
  }
}
