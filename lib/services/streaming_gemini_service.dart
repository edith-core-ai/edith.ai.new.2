import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../brains/edith_persona.dart';
import '../models/message.dart';
import '../models/attachment.dart';
import 'gemini_endpoints.dart';

/// Streaming Conversation Brain — v0.6
///
/// Same persona as GeminiService, but yields reply text chunk-by-chunk as
/// Gemini emits it. Model, keys and fallback live in [GeminiEndpoints].
class StreamingGeminiService {
  Stream<String> askStream(
    String userInput,
    List<Message> history, {
    Attachment? attachment,
    bool voiceMode = false,
  }) async* {
    final contents = [
      ...history.map((m) {
        final role = m.role == 'user' ? 'user' : 'model';
        final parts = <Map<String, dynamic>>[];
        if (m.attachment != null) {
          parts.add({
            'text': '[Attached file: ${m.attachment!.name}]\n\n'
                '${m.attachment!.textContent}',
          });
        }
        if (m.content.isNotEmpty) parts.add({'text': m.content});
        return {'role': role, 'parts': parts};
      }).where((c) => (c['parts'] as List).isNotEmpty),
      {
        'role': 'user',
        'parts': [
          if (attachment != null)
            {
              'text': '[Attached file: ${attachment.name}]\n\n'
                  '${attachment.textContent}',
            },
          {'text': userInput},
        ],
      },
    ];

    final modeHint = voiceMode
        ? 'VOICE MODE ACTIVE: reply conversationally and briefly.'
        : 'TEXT MODE ACTIVE: reply as detailed as needed.';

    final now = DateTime.now();
    final dateContext =
        'Current date and time: ${now.toIso8601String()} (device local time). $modeHint';

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': '$edithSystemPrompt\n\n$dateContext'}
        ]
      },
      'contents': contents,
      'tools': [
        {'google_search': {}}
      ],
    });

    final client = http.Client();
    try {
      final res = await GeminiEndpoints.openStream(client, body);
      if (res.statusCode != 200) {
        final errBody = await res.stream.bytesToString();
        throw Exception('Gemini stream failed (${res.statusCode}): $errBody');
      }
      await for (final line in res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final json = jsonDecode(payload);
          final parts =
              json['candidates']?[0]?['content']?['parts'] as List<dynamic>?;
          if (parts == null) continue;
          for (final p in parts) {
            final map = p as Map<String, dynamic>;
            if (map['thought'] == true) continue;
            final t = map['text'] as String?;
            if (t != null && t.isNotEmpty) yield t;
          }
        } catch (_) {
          // Skip a malformed chunk instead of killing the whole stream.
        }
      }
    } finally {
      client.close();
    }
  }
}
