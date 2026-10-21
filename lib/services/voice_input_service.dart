import 'package:speech_to_text/speech_to_text.dart';

/// Voice input — speech-to-text via the device's own recognition engine.
class VoiceInputService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  /// Called when the engine stops listening (done, silence or timeout).
  void Function()? onEnded;

  Future<bool> init() async {
    _available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') onEnded?.call();
      },
    );
    return _available;
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;

  Future<void> start(Function(String text, bool isFinal) onResult) async {
    if (!_available) return;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stop() async => _speech.stop();
}
