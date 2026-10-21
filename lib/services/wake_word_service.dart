import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wake-word listener: say "EDITH" and the voice screen opens.
///
/// Why it did not work before:
///  - the foreground service was never initialised, so Android refused to
///    keep the microphone alive;
///  - nothing asked for the microphone permission first;
///  - when the phone's speech engine ended a listening round (it does that
///    every few seconds, and on "no match") nothing restarted it.
///
/// Now: permission first, then the speech engine, then a foreground
/// service (best effort), and the listener restarts itself after every
/// round. If the service cannot start, listening still works while the
/// app is open.
class WakeWordService {
  final SpeechToText _speech = SpeechToText();
  Timer? _restart;
  bool _running = false;
  bool _fired = false;
  VoidCallback? _onWake;

  /// Plain-words reason when [start] returns false.
  String lastError = '';

  static const _names = {
    'edith', 'edyth', 'edythe', 'eadith', 'eddith', 'edis', 'edits',
  };

  /// Phone engines often write "edit" for "Edith", so "edit" only counts
  /// right after "hey" / "ok" / "okay".
  bool _isWake(String heard) {
    final words = heard
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (_names.contains(w)) return true;
      if (w == 'edit' &&
          i > 0 &&
          (words[i - 1] == 'hey' ||
              words[i - 1] == 'ok' ||
              words[i - 1] == 'okay')) {
        return true;
      }
    }
    return false;
  }

  Future<bool> start(VoidCallback onWake) async {
    if (_running) return true;
    _onWake = onWake;
    _fired = false;
    lastError = '';

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      lastError = 'Microphone permission is off. Turn it on in phone Settings.';
      return false;
    }

    final ok = await _speech.initialize(
      onError: (error) => _scheduleRestart(
        Duration(milliseconds: error.permanent ? 3000 : 600),
      ),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _scheduleRestart(const Duration(milliseconds: 400));
        }
      },
    );
    if (!ok) {
      lastError = 'Speech recognition is not available on this phone.';
      return false;
    }

    _running = true;
    await _startForeground();
    _listenOnce();
    return true;
  }

  Future<void> _startForeground() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'edith_wake_word',
          channelName: 'EDITH wake word',
          channelDescription: 'Keeps EDITH listening for her name.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
      await FlutterForegroundTask.requestNotificationPermission();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 7001,
        notificationTitle: 'E.D.I.T.H. listening',
        notificationText: 'Say "EDITH" to wake me.',
        callback: _fgCallback,
      );
    } catch (_) {
      // Listening still works while the app is open.
    }
  }

  void _scheduleRestart(Duration delay) {
    if (!_running || _fired) return;
    _restart?.cancel();
    _restart = Timer(delay, _listenOnce);
  }

  Future<void> _listenOnce() async {
    if (!_running || _fired || _speech.isListening) return;
    try {
      await _speech.listen(
        onResult: (result) {
          if (_fired || !_running) return;
          if (_isWake(result.recognizedWords)) {
            _fired = true;
            _speech.cancel();
            _onWake?.call();
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 6),
      );
    } catch (_) {
      _scheduleRestart(const Duration(seconds: 2));
    }
  }

  Future<void> stop() async {
    _running = false;
    _restart?.cancel();
    try {
      await _speech.cancel();
    } catch (_) {}
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void _fgCallback() {
  FlutterForegroundTask.setTaskHandler(_WakeTask());
}

class _WakeTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
