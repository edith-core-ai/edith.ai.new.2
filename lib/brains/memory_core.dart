import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';

/// Memory Core — what EDITH keeps about Hilal beyond single chats.
///
/// Three stores, all on the phone:
///  - facts: short lasting facts (lives in [SettingsService.memories]; this
///    class adds a privacy filter and near-duplicate detection in front);
///  - digests: one or two sentences per finished chat, so she can say
///    "last time you were working on X";
///  - pending lessons: rules she proposes for herself after a chat, which
///    Hilal approves in Self-improvement.
///
/// Call [MemoryCore.init] once in main() before runApp().
class MemoryCore {
  MemoryCore._();

  static SharedPreferences? _p;

  static const _kDigests = 'edith_digests';
  static const _kPending = 'edith_pending_lessons';
  static const _kReflected = 'edith_reflected_counts';

  static const int maxDigests = 12;
  static const int maxPending = 10;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> _prefs() async =>
      _p ??= await SharedPreferences.getInstance();

  // ───────────── Facts ─────────────

  static final RegExp _secretWords = RegExp(
    r'password|passcode|passphrase|\bpin\b|\bcvv\b|\botp\b|card number|'
    r'secret key|api key|private key|seed phrase',
    caseSensitive: false,
  );
  static final RegExp _longNumber = RegExp(r'\d[\d\s-]{10,}\d');

  /// False for anything that looks like a password, card or ID number.
  static bool isSafeToStore(String text) =>
      !_secretWords.hasMatch(text) && !_longNumber.hasMatch(text);

  static Set<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 3)
      .toSet();

  /// True when [fact] says (almost) the same as something already saved.
  static bool isNearDuplicate(String fact) {
    final a = _words(fact);
    if (a.isEmpty) return false;
    for (final existing in SettingsService.memories) {
      final b = _words(existing);
      if (b.isEmpty) continue;
      final shared = a.intersection(b).length;
      final smaller = a.length < b.length ? a.length : b.length;
      if (smaller > 0 && shared / smaller >= 0.8) return true;
    }
    return false;
  }

  /// Saves a fact unless it is private data or already known.
  /// Returns true if it was saved.
  static Future<bool> addFact(String fact) async {
    final f = fact.trim();
    if (f.isEmpty || f.length > 300) return false;
    if (!isSafeToStore(f)) return false;
    if (isNearDuplicate(f)) return false;
    await SettingsService.addMemory(f);
    return true;
  }

  // ───────────── Conversation digests ─────────────

  /// Each entry is "yyyy-MM-dd|text".
  static List<String> get digests => _p?.getStringList(_kDigests) ?? const [];

  static String _today() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  static Future<void> addDigest(String text) async {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || !isSafeToStore(t)) return;
    final clipped = t.length > 240 ? t.substring(0, 240) : t;
    final list = List<String>.from(digests);
    if (list.any((e) => e.endsWith('|$clipped'))) return;
    list.add('${_today()}|$clipped');
    while (list.length > maxDigests) {
      list.removeAt(0);
    }
    await (await _prefs()).setStringList(_kDigests, list);
  }

  static Future<void> removeDigestAt(int index) async {
    final list = List<String>.from(digests);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await (await _prefs()).setStringList(_kDigests, list);
  }

  static Future<void> clearDigests() async {
    await (await _prefs()).remove(_kDigests);
  }

  /// "2026-10-21|text" → text
  static String digestText(String entry) {
    final i = entry.indexOf('|');
    return i == -1 ? entry : entry.substring(i + 1);
  }

  /// "2026-10-21|text" → 2026-10-21
  static String digestDate(String entry) {
    final i = entry.indexOf('|');
    return i == -1 ? '' : entry.substring(0, i);
  }

  /// Block added to her prompt (empty if there are no digests).
  static String get digestBlock {
    final d = digests;
    if (d.isEmpty) return '';
    final lines = d.map((e) => '- ${digestDate(e)}: ${digestText(e)}').join('\n');
    return '\n\nRECENT CONVERSATIONS (what you and Hilal talked about, '
        'oldest first; mention them only when they help)\n$lines';
  }

  // ───────────── Lessons waiting for approval ─────────────

  static List<String> get pendingLessons =>
      _p?.getStringList(_kPending) ?? const [];

  static Future<void> addPendingLesson(String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > 240) return;
    final low = t.toLowerCase();
    if (SettingsService.lessons.any((e) => e.toLowerCase() == low)) return;
    final list = List<String>.from(pendingLessons);
    if (list.any((e) => e.toLowerCase() == low)) return;
    list.add(t);
    while (list.length > maxPending) {
      list.removeAt(0);
    }
    await (await _prefs()).setStringList(_kPending, list);
  }

  static Future<void> removePendingLesson(String text) async {
    final list = List<String>.from(pendingLessons)..remove(text);
    await (await _prefs()).setStringList(_kPending, list);
  }

  // ───────────── Which chats she already learned from ─────────────

  static Map<String, int> _counts() {
    final raw = _p?.getString(_kReflected);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// How many messages of this chat were already read for learning.
  static int reflectedCount(String key) => _counts()[key] ?? 0;

  static Future<void> setReflectedCount(String key, int count) async {
    final m = _counts();
    m[key] = count;
    // Keep the table small.
    if (m.length > 60) {
      final keys = m.keys.toList();
      for (final k in keys.take(m.length - 60)) {
        m.remove(k);
      }
    }
    await (await _prefs()).setString(_kReflected, jsonEncode(m));
  }
}
