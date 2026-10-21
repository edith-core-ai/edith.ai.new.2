/// BCI Command Layer — v0.6
///
/// Translates raw EEG-derived signals (attention, meditation, blink)
/// into simple command intents. This is the same approach BrainCo
/// uses for mind-controlled robots [citation:9][citation:13]: read
/// brain state, decode intent, trigger action.
///
/// IMPORTANT: This is NOT mind-reading. It reads broad brain-state
/// signals (focus, calm) plus deliberate eye blinks. Complex thought
/// decoding requires an implant and is not possible with a consumer
/// EEG headband [citation:1].
class BciCommand {
  final String action;
  final double confidence;
  final DateTime timestamp;

  BciCommand({
    required this.action,
    required this.confidence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Command intents the BCI layer can emit.
class BciIntent {
  static const String confirm = 'CONFIRM';
  static const String cancel = 'CANCEL';
  static const String wake = 'WAKE';
  static const String scrollUp = 'SCROLL_UP';
  static const String scrollDown = 'SCROLL_DOWN';
}

class BciCommandDecoder {
  /// Sustained focus threshold — attention score above this for
  /// [_focusHoldMs] milliseconds triggers a command.
  static const int focusThreshold = 70;
  static const int _focusHoldMs = 3000;

  /// Blink detection: a sharp attention dip followed by a rebound
  /// within [_blinkWindowMs] is treated as a deliberate blink.
  static const int _blinkWindowMs = 400;

  double? _lastAttention;
  DateTime? _focusStart;
  final List<DateTime> _recentBlinkTimes = [];

  /// Feed one EEG sample. Returns a command if one was triggered,
  /// otherwise null.
  BciCommand? feed({
    required double attention,
    required double meditation,
    required double blinkStrength,
  }) {
    final now = DateTime.now();

    // --- Blink detection ---
    if (blinkStrength > 0.7) {
      _recentBlinkTimes.add(now);
      _recentBlinkTimes.removeWhere(
        (t) => now.difference(t).inMilliseconds > _blinkWindowMs,
      );

      // Double blink = deliberate signal
      if (_recentBlinkTimes.length >= 2) {
        _recentBlinkTimes.clear();

        // Focused double-blink = confirm
        if (attention >= 60) {
          return BciCommand(
            action: BciIntent.confirm,
            confidence: attention / 100,
          );
        }
        // Relaxed double-blink = cancel
        if (meditation >= 60) {
          return BciCommand(
            action: BciIntent.cancel,
            confidence: meditation / 100,
          );
        }
      }
    }

    // --- Sustained focus detection (wake-word substitute) ---
    if (attention >= focusThreshold) {
      _focusStart ??= now;
      final held = now.difference(_focusStart!).inMilliseconds;
      if (held >= _focusHoldMs) {
        _focusStart = null;
        return BciCommand(
          action: BciIntent.wake,
          confidence: attention / 100,
        );
      }
    } else {
      _focusStart = null;
    }

    _lastAttention = attention;
    return null;
  }

  /// Reset internal state (call when disconnecting).
  void reset() {
    _lastAttention = null;
    _focusStart = null;
    _recentBlinkTimes.clear();
  }
}
