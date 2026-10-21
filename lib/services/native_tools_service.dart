import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Dart bridge to native Tier 3 capabilities:
///   - Direct SMS send (no app opens)
///   - Contacts read
///   - Notification listener read
class NativeToolsService {
  static const _channel = MethodChannel('edith/native_tools');

  /// Asks for a permission. If the user said "don't ask again", opens the
  /// app's system settings page so they can switch it on by hand.
  Future<void> _need(Permission permission, String label) async {
    final status = await permission.request();
    if (status.isGranted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception(
          '$label permission is blocked. I opened the app settings: tap '
          'Permissions, then allow $label, then ask me again.');
    }
    throw Exception(
        '$label permission was denied. Ask again and tap Allow when the '
        'phone asks.');
  }

  // ─────────── SMS ───────────

  Future<bool> sendSmsDirect(String phone, String message) async {
    await _need(Permission.sms, 'SMS');
    final ok = await _channel.invokeMethod<bool>('sendSms', {
      'phone': phone,
      'message': message,
    });
    return ok ?? false;
  }

  // ─────────── Contacts ───────────

  Future<List<Map<String, String>>> readContacts() async {
    await _need(Permission.contacts, 'Contacts');
    final raw = await _channel.invokeMethod<List<dynamic>>('readContacts');
    if (raw == null) return [];
    return raw
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  /// Finds a phone number by fuzzy name match. Returns null if no match.
  Future<String?> lookupContactNumber(String nameFragment) async {
    final contacts = await readContacts();
    final needle = nameFragment.toLowerCase();
    for (final c in contacts) {
      if ((c['name'] ?? '').toLowerCase().contains(needle)) {
        return c['number'];
      }
    }
    return null;
  }

  // ─────────── Notifications ───────────

  Future<bool> isNotificationListenerEnabled() async {
    final ok = await _channel
        .invokeMethod<bool>('isNotificationListenerEnabled');
    return ok ?? false;
  }

  Future<List<Map<String, String>>> readNotifications(
      {int limit = 10}) async {
    if (!await isNotificationListenerEnabled()) {
      try {
        await const AndroidIntent(
          action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
        ).launch();
      } catch (_) {}
      throw Exception(
          'Notification access is off. I opened the page: switch on E.D.I.T.H., '
          'then ask me again.');
    }
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'readNotifications',
      {'limit': limit},
    );
    if (raw == null) return [];
    return raw
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }
}