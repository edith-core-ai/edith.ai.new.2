import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'gemini_endpoints.dart';
import 'settings_service.dart';

/// Gemini's own speech engine: sends text, gets back spoken audio.
/// Uses the same Gemini key(s) as chat, so no extra account is needed.
class GeminiTtsService {
  static const List<String> models = [
    'gemini-2.5-flash-preview-tts',
    'gemini-2.5-pro-preview-tts',
  ];

  static const List<String> voices = [
    'Kore', 'Aoede', 'Leda', 'Zephyr', 'Puck', 'Charon', 'Fenrir', 'Orus',
  ];

  /// Plain-words reason for the last failure (empty when fine).
  static String lastError = '';

  static bool get available => SettingsService.hasGeminiKey;

  /// Returns a playable WAV, or null if every try failed.
  static Future<Uint8List?> synthesize(String text) async {
    lastError = '';
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final spoken = clean.length > 1800 ? clean.substring(0, 1800) : clean;

    final keys = <String>{
      for (final a in GeminiEndpoints.attempts()) a.key,
    }.toList();

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': spoken}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': SettingsService.geminiVoice}
          }
        }
      },
    });

    for (final model in models) {
      for (final key in keys) {
        try {
          final res = await http
              .post(
                GeminiEndpoints.url(model),
                headers: GeminiEndpoints.headers(key),
                body: body,
              )
              .timeout(const Duration(seconds: 40));
          if (res.statusCode != 200) {
            lastError = 'Gemini voice error ${res.statusCode}';
            continue;
          }
          final parts = jsonDecode(res.body)['candidates']?[0]?['content']
              ?['parts'] as List<dynamic>?;
          final data = parts?.firstWhere(
            (p) => p['inlineData'] != null,
            orElse: () => null,
          )?['inlineData']?['data'] as String?;
          if (data == null) {
            lastError = 'Gemini voice returned no audio';
            continue;
          }
          return _pcmToWav(base64Decode(data));
        } catch (e) {
          lastError = 'Gemini voice failed: $e';
        }
      }
    }
    return null;
  }

  /// Gemini returns raw 16-bit mono PCM at 24 kHz. Wrap it so any player
  /// can play it.
  static Uint8List _pcmToWav(Uint8List pcm) {
    const sampleRate = 24000;
    const channels = 1;
    const bits = 16;
    final byteRate = sampleRate * channels * bits ~/ 8;
    final h = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, byteRate, Endian.little);
    h.setUint16(32, channels * bits ~/ 8, Endian.little);
    h.setUint16(34, bits, Endian.little);
    str(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
  }
}
