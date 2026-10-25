import 'dart:convert';
import '../brains/memory_core.dart';
import '../models/message.dart';
import 'edith_prefs.dart';
import 'gemini_endpoints.dart';
import 'grok_service.dart';
import 'proactive_service.dart';
import 'settings_service.dart';

/// What one round of learning produced.
class ReflectionResult {
  final int facts;
  final bool digest;
  final int lessons;
  final int followUps;
  const ReflectionResult(this.facts, this.digest, this.lessons, this.followUps);

  static const ReflectionResult none = ReflectionResult(0, false, 0, 0);

  bool get isEmpty => facts == 0 && !digest && lessons == 0 && followUps == 0;
}

/// Learning after each chat.
///
/// When a chat is left (new chat, another chat, app to background, voice
/// call ended), she reads what was new in it and decides what is worth
/// keeping:
///  - lasting facts about Hilal → memory (checked for secrets and repeats);
///  - a one-line digest of the chat → "recent conversations" in her prompt;
///  - rules for herself, only if he corrected her → wait for his approval
///    in Self-improvement;
///  - things he said are coming up → a follow-up message later (needs
///    proactive messages switched on).
///
/// Best effort: any failure is swallowed so chatting is never affected.
class ReflectionService {
  ReflectionService._();

  static bool _busy = false;

  static String _clip(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  /// [key] identifies the chat (thread id, or any stable id for a voice
  /// call). [messages] is the whole chat so far. Nothing happens unless at
  /// least four new messages arrived since the last time.
  static Future<ReflectionResult> reflect(
    String key,
    List<Message> messages, {
    bool force = false,
  }) async {
    if (_busy) return ReflectionResult.none;
    if (!EdithPrefs.autoLearn && !force) return ReflectionResult.none;
    if (!SettingsService.hasGeminiKey && !GrokService.available) {
      return ReflectionResult.none;
    }

    final real = messages
        .where((m) =>
            m.content.trim().isNotEmpty &&
            !m.content.startsWith('[Sent') &&
            !m.content.startsWith('[Attached'))
        .toList();
    final userCount = real.where((m) => m.role == 'user').length;
    final done = MemoryCore.reflectedCount(key);
    if (userCount < 2) return ReflectionResult.none;
    if (!force && real.length - done < 4) return ReflectionResult.none;
    if (force && real.length - done < 2) return ReflectionResult.none;

    _busy = true;
    try {
      final recent = real.length > 30 ? real.sublist(real.length - 30) : real;
      final transcript = StringBuffer();
      for (final m in recent) {
        transcript.writeln(
            '${m.role == 'user' ? 'HILAL' : 'EDITH'}: ${_clip(m.content.trim(), 500)}');
      }

      final known = SettingsService.memories.map((e) => '- $e').join('\n');
      final lessons = SettingsService.lessons.map((e) => '- $e').join('\n');
      final now = DateTime.now();

      const system =
          'You are the memory of a personal AI assistant named EDITH. You '
          'read a conversation between EDITH and her user Hilal and decide '
          'what is worth remembering. Reply with one JSON object only.';

      final user = 'Now: ${now.toIso8601String()} (local time).\n\n'
          'ALREADY REMEMBERED ABOUT HILAL:\n${known.isEmpty ? '(nothing)' : known}\n\n'
          'EXISTING RULES FOR EDITH:\n${lessons.isEmpty ? '(none)' : lessons}\n\n'
          'CONVERSATION:\n$transcript\n'
          'Return JSON with exactly these keys:\n'
          '{\n'
          '  "facts": [up to 4 short lasting facts about Hilal: preferences, '
          'people in his life, projects, plans, goals, routines. One sentence '
          'each, starting with "Hilal". Skip anything already remembered, '
          'one-off trivia, and anything that only mattered in this chat. '
          'NEVER include passwords, PINs, card or ID numbers],\n'
          '  "digest": "one or two sentences: what this chat was about and '
          'any open thread (something he said he would do, or a question '
          'still unanswered). Empty string if the chat was trivial.",\n'
          '  "lessons": [up to 2 rules for EDITH\'s own behaviour, ONLY if '
          'Hilal corrected her or showed annoyance. Imperative, one line. '
          'Empty list otherwise],\n'
          '  "followups": [up to 2 objects {"text": "friendly check-in '
          'message EDITH would send, 120 characters at most", "at": "ISO '
          '8601 local date-time to send it"}. ONLY for things Hilal said are '
          'coming up (exam, trip, interview, meeting, deadline, '
          'appointment); send it shortly after the event. Empty list '
          'otherwise]\n'
          '}';

      final raw = await _askModel(system, user);
      if (raw == null) return ReflectionResult.none;
      final data = _parseJson(raw);
      if (data == null) return ReflectionResult.none;

      var savedFacts = 0;
      for (final f in (data['facts'] as List<dynamic>? ?? const []).take(4)) {
        if (await MemoryCore.addFact(f.toString())) savedFacts++;
      }

      var savedDigest = false;
      final digest = (data['digest'] ?? '').toString().trim();
      if (digest.isNotEmpty && MemoryCore.isSafeToStore(digest)) {
        await MemoryCore.addDigest(digest);
        savedDigest = true;
      }

      var pending = 0;
      for (final l in (data['lessons'] as List<dynamic>? ?? const []).take(2)) {
        final before = MemoryCore.pendingLessons.length;
        await MemoryCore.addPendingLesson(l.toString());
        if (MemoryCore.pendingLessons.length > before) pending++;
      }

      var followUps = 0;
      for (final f in (data['followups'] as List<dynamic>? ?? const []).take(2)) {
        if (f is! Map) continue;
        final text = (f['text'] ?? '').toString();
        final at = DateTime.tryParse((f['at'] ?? '').toString());
        if (text.isEmpty || at == null) continue;
        if (await ProactiveService.scheduleFollowUp(text, at)) followUps++;
      }

      await MemoryCore.setReflectedCount(key, real.length);
      return ReflectionResult(savedFacts, savedDigest, pending, followUps);
    } catch (_) {
      return ReflectionResult.none;
    } finally {
      _busy = false;
    }
  }

  /// Gemini first (JSON mode), Grok if Gemini fails.
  static Future<String?> _askModel(String system, String user) async {
    if (SettingsService.hasGeminiKey) {
      try {
        final body = jsonEncode({
          'system_instruction': {
            'parts': [
              {'text': system}
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': user}
              ]
            }
          ],
          'generationConfig': {'responseMimeType': 'application/json'},
        });
        final res = await GeminiEndpoints.post(body);
        if (res.statusCode == 200) {
          final parts = jsonDecode(res.body)['candidates']?[0]?['content']
              ?['parts'] as List<dynamic>?;
          final text = parts
              ?.where((p) => p['thought'] != true)
              .map((p) => (p['text'] ?? '').toString())
              .join('\n');
          if (text != null && text.trim().isNotEmpty) return text;
        }
      } catch (_) {}
    }
    if (GrokService.available) {
      try {
        return await GrokService.chat(system, user);
      } catch (_) {}
    }
    return null;
  }

  /// Reads the first {...} block, even if the model added extra words.
  static Map<String, dynamic>? _parseJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final v = jsonDecode(raw.substring(start, end + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
