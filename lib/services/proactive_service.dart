import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../brains/edith_persona.dart';
import 'edith_prefs.dart';
import 'gemini_endpoints.dart';
import 'settings_service.dart';

/// One notification waiting in the phone's alarm list.
class ScheduledItem {
  final int id;
  final DateTime at;
  final String title;
  final String text;
  final bool daily;
  final String kind; // 'proactive' | 'reminder'

  const ScheduledItem({
    required this.id,
    required this.at,
    required this.title,
    required this.text,
    required this.daily,
    required this.kind,
  });
}

/// EDITH speaks first.
///
/// The phone's own alarm clock (native Kotlin, `EdithProactive.kt`) fires the
/// notification, so it works when the app is closed and after a reboot.
/// This class decides WHAT to say and WHEN:
///  - a morning message and an evening check-in every day, written by
///    Gemini from what she knows about Hilal and refreshed whenever the app
///    is opened;
///  - follow-ups she plans after a chat ("how did the exam go?");
///  - reminders Hilal asks for (`remind_me` tool).
///
/// Tapping a notification opens the app with her message as the first line
/// of a new chat ([onTap]).
class ProactiveService {
  ProactiveService._();

  static const MethodChannel _ch = MethodChannel('edith/proactive');

  static const int morningId = 9001;
  static const int eveningId = 9002;

  /// Set by the home screen. Called with (kind, text) when a notification
  /// is tapped.
  static void Function(String kind, String text)? onTap;

  static bool _ready = false;

  /// Call once from main().
  static void init() {
    if (_ready) return;
    _ready = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'tapped') {
        _deliver(call.arguments as String?);
      }
      return null;
    });
  }

  static void _deliver(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final text = (m['text'] ?? '').toString();
      if (text.isEmpty) return;
      onTap?.call((m['kind'] ?? 'proactive').toString(), text);
    } catch (_) {}
  }

  /// Cold start: the app was opened by tapping one of her notifications.
  static Future<void> deliverLaunchPayload() async {
    try {
      final p = await _ch.invokeMethod<String>('takeLaunchPayload');
      _deliver(p);
    } catch (_) {}
  }

  // ───────────── Permission ─────────────

  static Future<bool> hasPermission() async {
    try {
      return await Permission.notification.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> ensurePermission() async {
    try {
      final s = await Permission.notification.request();
      return s.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// True when the phone allows alarms at the exact minute.
  static Future<bool> canExact() async {
    try {
      return await _ch.invokeMethod<bool>('canExact') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ───────────── Alarm list (native) ─────────────

  /// Returns 'exact', 'approx', or null if it could not be scheduled.
  static Future<String?> schedule({
    required int id,
    required DateTime at,
    required String text,
    String title = 'EDITH',
    bool daily = false,
    String kind = 'proactive',
  }) async {
    try {
      return await _ch.invokeMethod<String>('schedule', {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'text': text,
        'daily': daily,
        'kind': kind,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await _ch.invokeMethod<bool>('cancel', {'id': id});
    } catch (_) {}
  }

  static Future<List<ScheduledItem>> list() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('list') ?? [];
      final out = <ScheduledItem>[];
      for (final e in raw) {
        final m = Map<String, dynamic>.from(e as Map);
        out.add(ScheduledItem(
          id: (m['id'] as num).toInt(),
          at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
          title: (m['title'] ?? '').toString(),
          text: (m['text'] ?? '').toString(),
          daily: m['daily'] == true,
          kind: (m['kind'] ?? 'proactive').toString(),
        ));
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return [];
    }
  }

  // ───────────── Daily messages ─────────────

  /// Next time the clock shows [minutes] after midnight.
  static DateTime nextAt(int minutes) {
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (!t.isAfter(now.add(const Duration(minutes: 1)))) {
      t = DateTime(now.year, now.month, now.day + 1, minutes ~/ 60, minutes % 60);
    }
    return t;
  }

  /// Rewrites and re-arms the morning and evening messages. Safe to call
  /// often: new text is only written when the old one is over 16 hours
  /// old (or [force] is true), so it costs at most two AI calls a day.
  static Future<void> refreshDaily({bool force = false}) async {
    if (!EdithPrefs.proactive) {
      await cancel(morningId);
      await cancel(eveningId);
      return;
    }
    await _slot(morningId, EdithPrefs.morningOn, EdithPrefs.morningMinutes,
        'morning', force);
    await _slot(eveningId, EdithPrefs.eveningOn, EdithPrefs.eveningMinutes,
        'evening', force);
  }

  static Future<void> _slot(
      int id, bool on, int minutes, String name, bool force) async {
    if (!on) {
      await cancel(id);
      return;
    }
    final textKey = 'edith_slot_text_$name';
    final timeKey = 'edith_slot_time_$name';
    var text = EdithPrefs.getString(textKey);
    final made = int.tryParse(EdithPrefs.getString(timeKey)) ?? 0;
    final ageHours = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(made))
        .inHours;
    if (text.isEmpty || force || ageHours >= 16) {
      final fresh = await _compose(name);
      if (fresh != null) {
        text = fresh;
        await EdithPrefs.putString(textKey, text);
        await EdithPrefs.putString(
            timeKey, DateTime.now().millisecondsSinceEpoch.toString());
      }
    }
    if (text.isEmpty) {
      text = name == 'morning'
          ? 'Morning, Boss. Want your day laid out?'
          : 'Evening, Boss. How did today go?';
    }
    await schedule(id: id, at: nextAt(minutes), text: text, daily: true);
  }

  /// One short message in her voice, or null if the AI call failed.
  static Future<String?> _compose(String slot) async {
    if (!SettingsService.hasGeminiKey) return null;
    try {
      final ask = slot == 'morning'
          ? 'a morning message to start his day'
          : 'an evening check-in on how his day went';
      final body = jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': '$edithCharacter$edithMemoryBlock$edithLessonsBlock'}
          ]
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'Date and time now: ${DateTime.now().toIso8601String()}.\n'
                    'Write $ask, as a push notification from you to Hilal.\n'
                    'Rules: one or two short sentences, 120 characters at '
                    'most in total. Personal: use what you know about him '
                    'and his recent chats when it fits. Do not state live '
                    'facts (weather, news, prices). No hashtags. At most one '
                    'emoji. Reply with the message text only.'
              }
            ]
          }
        ],
      });
      final res = await GeminiEndpoints.post(body);
      if (res.statusCode != 200) return null;
      final parts = jsonDecode(res.body)['candidates']?[0]?['content']?['parts']
          as List<dynamic>?;
      if (parts == null) return null;
      var text = parts
          .where((p) => p['thought'] != true)
          .map((p) => (p['text'] ?? '').toString())
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('"', '')
          .trim();
      if (text.isEmpty) return null;
      if (text.length > 160) text = '${text.substring(0, 157)}...';
      return text;
    } catch (_) {
      return null;
    }
  }

  // ───────────── Follow-ups she plans after a chat ─────────────

  /// Plans "how did it go?" for something Hilal said is coming up.
  /// Returns true if it was scheduled.
  static Future<bool> scheduleFollowUp(String text, DateTime when) async {
    if (!EdithPrefs.proactive) return false;
    final t = text.trim();
    if (t.isEmpty || t.length > 200) return false;
    if (!await hasPermission()) return false;

    final now = DateTime.now();
    var at = when;
    if (at.isBefore(now)) return false;
    if (at.isAfter(now.add(const Duration(days: 14)))) return false;
    // Never wake him at night.
    if (at.hour < 9) at = DateTime(at.year, at.month, at.day, 9, 0);
    if (at.hour >= 21) at = DateTime(at.year, at.month, at.day, 20, 30);
    if (at.isBefore(now.add(const Duration(minutes: 15)))) return false;

    final existing = await list();
    if (existing.any((e) => e.text == t)) return false;
    if (existing.where((e) => e.kind == 'proactive' && !e.daily).length >= 10) {
      return false;
    }
    final id = 100000 + ((t.hashCode ^ at.millisecondsSinceEpoch) & 0xFFFFF);
    final r = await schedule(id: id, at: at, text: t, daily: false);
    return r != null;
  }

  // ───────────── Reminders (remind_me tool) ─────────────

  static Future<String> remind({
    required String text,
    required DateTime at,
    bool daily = false,
  }) async {
    if (!at.isAfter(DateTime.now())) {
      return 'That time has already passed. Ask me for a time in the future.';
    }
    if (!await ensurePermission()) {
      return 'Notifications are off for EDITH, so I cannot remind you. Turn '
          'them on in phone Settings, then ask again.';
    }
    final id = 200000 + ((text.hashCode ^ at.millisecondsSinceEpoch) & 0xFFFFF);
    final r = await schedule(
      id: id,
      at: at,
      text: text,
      title: 'Reminder',
      daily: daily,
      kind: 'reminder',
    );
    if (r == null) return 'I could not set that reminder on this phone.';
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final when =
        '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} $h:$m';
    final precision = r == 'exact'
        ? ''
        : ' (the phone may deliver it a few minutes late; allow exact alarms '
            'for EDITH in phone Settings for perfect timing)';
    return 'Reminder set for $when${daily ? ', every day' : ''}$precision. id=$id';
  }
}
