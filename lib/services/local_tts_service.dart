import 'package:flutter_tts/flutter_tts.dart';

/// Voice Brain — local/free path.
///
/// Uses the device's own built-in speech engine (same tech behind
/// screen readers and browser "read aloud"). Completely free and
/// unlimited — no API key, no monthly cap, works offline. This is
/// EDITH's default voice.
///
/// It sounds more generic than the ElevenLabs voice (see
/// elevenlabs_service.dart), which stays available as an optional
/// "nicer voice" you tap for, since that one costs monthly credits.
class LocalTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.setLanguage('en-GB'); // British-leaning, matches persona
    await _tts.awaitSpeakCompletion(true); // speak() returns when done
    await _tts.setPitch(0.95);
    await _tts.setSpeechRate(0.48);
    _configured = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureConfigured();
    await _tts.stop(); // cut off any previous speech first
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
