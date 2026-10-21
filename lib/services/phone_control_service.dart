import 'package:flutter/services.dart';

/// Bridge to the native Android AccessibilityService.
///
/// Requires the user to enable "EDITH Control" in
/// Settings → Accessibility. If not enabled, isEnabled() returns false
/// and every other call is a no-op.
class PhoneControlService {
  static const _channel = MethodChannel('edith/accessibility');

  Future<bool> isEnabled() async {
    final r = await _channel.invokeMethod<bool>('isEnabled');
    return r ?? false;
  }

  /// 'running', 'enabled' (switched on but the phone is not running it) or
  /// 'off'.
  Future<String> status() async {
    final r = await _channel.invokeMethod<String>('status');
    return r ?? 'off';
  }

  Future<void> back() => _channel.invokeMethod('performBack');
  Future<void> home() => _channel.invokeMethod('performHome');
  Future<void> recents() => _channel.invokeMethod('performRecents');

  Future<String> readScreen() async {
    final r = await _channel.invokeMethod<String>('readScreen');
    return r ?? '';
  }

  Future<bool> tapByText(String text) async {
    final r = await _channel.invokeMethod<bool>('tapByText', {'text': text});
    return r ?? false;
  }

  Future<bool> typeIntoFocused(String text) async {
    final r =
        await _channel.invokeMethod<bool>('typeIntoFocused', {'text': text});
    return r ?? false;
  }

  Future<bool> scroll({bool forward = true}) async {
    final r = await _channel.invokeMethod<bool>('scroll', {'forward': forward});
    return r ?? false;
  }

  /// Base64 JPEG of the current screen, or null (needs Android 11+ and the
  /// Accessibility service running).
  Future<String?> screenshot() async {
    try {
      return await _channel.invokeMethod<String>('screenshot');
    } catch (_) {
      return null;
    }
  }

  Future<String> currentApp() async {
    final r = await _channel.invokeMethod<String>('currentApp');
    return r ?? '';
  }

  /// Opens an installed app by its visible name. Returns the real app name,
  /// or null if no installed app matches.
  Future<String?> launchApp(String name) async {
    return _channel.invokeMethod<String>('launchApp', {'name': name});
  }
}
