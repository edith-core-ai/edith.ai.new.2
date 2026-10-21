import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'gemini_tts_service.dart';
import 'local_tts_service.dart';
import 'settings_service.dart';

/// EDITH's mouth. Gemini's speech engine first; the phone's own voice if
/// Gemini cannot speak (no key, no internet, limit reached).
class VoiceOutService {
  final AudioPlayer _player = AudioPlayer();
  final LocalTtsService _local = LocalTtsService();
  Completer<void>? _playing;

  /// Why the last line fell back to the phone voice (empty if it did not).
  String lastNote = '';

  /// Speaks and returns when the speech has finished (or was stopped).
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await stop();
    lastNote = '';

    if (SettingsService.useGeminiVoice && GeminiTtsService.available) {
      final wav = await GeminiTtsService.synthesize(text);
      if (wav != null) {
        try {
          final done = Completer<void>();
          _playing = done;
          late StreamSubscription sub;
          sub = _player.onPlayerComplete.listen((_) {
            if (!done.isCompleted) done.complete();
            sub.cancel();
          });
          await _player.play(BytesSource(wav));
          await done.future;
          return;
        } catch (e) {
          lastNote = 'Audio playback failed: $e';
        }
      } else {
        lastNote = GeminiTtsService.lastError;
      }
    }
    await _local.speak(text);
  }

  Future<void> stop() async {
    final p = _playing;
    if (p != null && !p.isCompleted) p.complete();
    try {
      await _player.stop();
    } catch (_) {}
    await _local.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
