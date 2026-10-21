import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

/// Voice Brain — v0.2
///
/// Converts E.D.I.T.H.'s text replies into spoken audio via ElevenLabs.
/// Free tier: ~10 min of audio per month, so this is triggered per-message
/// (tap to hear) rather than auto-played on every reply, to make that
/// budget last. When EDITH becomes a real installed app, this same
/// service can be wired to auto-speak, plus wake-word ("EDITH...")
/// listening becomes possible with native background mic access.
class ElevenLabsService {
  static const _endpointBase = 'https://api.elevenlabs.io/v1/text-to-speech';

  /// Returns raw MP3 audio bytes for the given text, spoken in EDITH's voice.
  Future<List<int>> synthesize(String text) async {
    final url = Uri.parse('$_endpointBase/${SettingsService.elevenLabsVoiceId}');

    final response = await http.post(
      url,
      headers: {
        'xi-api-key': SettingsService.elevenLabsApiKey,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      },
      body: jsonEncode({
        'text': text,
        'model_id': 'eleven_multilingual_v2',
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'ElevenLabs request failed (${response.statusCode}): ${response.body}');
    }

    return response.bodyBytes;
  }
}
