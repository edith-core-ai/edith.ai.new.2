import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps a live voice call running when the screen turns off or another
/// app is in front.
///
/// Android only lets an app use the microphone in the background while a
/// foreground service of type "microphone" is running. The service shows
/// one quiet notification ("E.D.I.T.H. is on a call") and holds a wake lock
/// so the phone does not sleep mid-sentence.
///
/// It shares the foreground service with the wake-word listener: if that
/// one is already running it is reused, and put back to its own text when
/// the call ends.
class CallKeepAlive {
  CallKeepAlive._();

  static bool _startedByUs = false;

  static Future<void> start() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'edith_call',
          channelName: 'EDITH call',
          channelDescription: 'Keeps a voice call with EDITH running.',
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
          allowWifiLock: true,
        ),
      );
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'E.D.I.T.H. is on a call',
          notificationText: 'Open the app to hang up.',
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 7002,
        notificationTitle: 'E.D.I.T.H. is on a call',
        notificationText: 'Open the app to hang up.',
        callback: _callbackEntry,
      );
      _startedByUs = true;
    } catch (_) {
      // The call still works while the app is on screen.
    }
  }

  static Future<void> stop() async {
    try {
      if (_startedByUs) {
        _startedByUs = false;
        await FlutterForegroundTask.stopService();
      } else if (await FlutterForegroundTask.isRunningService) {
        // The wake-word listener owns the service: restore its text.
        await FlutterForegroundTask.updateService(
          notificationTitle: 'E.D.I.T.H. listening',
          notificationText: 'Say "EDITH" to wake me.',
        );
      }
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void _callbackEntry() {
  FlutterForegroundTask.setTaskHandler(_CallTask());
}

class _CallTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
