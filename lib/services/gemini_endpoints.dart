import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

/// One try: a model plus a key.
class GeminiAttempt {
  final String model;
  final String key;
  const GeminiAttempt(this.model, this.key);
}

/// Shared Gemini plumbing for every service (chat, tools, vision, voice,
/// phone agent). One place decides:
///  - which model to call,
///  - which key to use (main key, then backup key),
///  - when to fall back (429, 404 or a 5xx server error) to the next
///    attempt: same model with the backup key, then the lighter model.
///
/// The key goes in the `x-goog-api-key` header, never in the URL, so it
/// cannot leak into logs or error messages.
class GeminiEndpoints {
  GeminiEndpoints._();

  static const String primaryModel = 'gemini-3.6-flash';
  static const String liteModel = 'gemini-3.5-flash-lite';
  static const String noKeyMarker = 'NO_GEMINI_KEY';

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Keys that just failed with a limit error are skipped for a few
  /// minutes, so each message does not waste time retrying a dead key.
  static final Map<String, DateTime> _cooldown = {};

  static bool _cooling(String model, String key) {
    final t = _cooldown['$model|$key'];
    return t != null && DateTime.now().isBefore(t);
  }

  static void _markFailed(String model, String key) {
    _cooldown['$model|$key'] =
        DateTime.now().add(const Duration(minutes: 3));
  }

  static bool _usable(String k) => k.isNotEmpty && !k.startsWith('PASTE_');

  /// Ordered list of (model, key) tries. Throws if no key is set at all.
  static List<GeminiAttempt> attempts() {
    final keys = <String>[
      if (_usable(SettingsService.geminiApiKey)) SettingsService.geminiApiKey,
      if (_usable(SettingsService.geminiApiKeyBackup))
        SettingsService.geminiApiKeyBackup,
    ];
    if (keys.isEmpty) throw Exception(noKeyMarker);
    final all = [
      for (final model in [primaryModel, liteModel])
        for (final key in keys) GeminiAttempt(model, key),
    ];
    // Skip tries that failed a moment ago, but never end up with none.
    final fresh = all.where((a) => !_cooling(a.model, a.key)).toList();
    return fresh.isEmpty ? all : fresh;
  }

  static Uri url(String model, {bool stream = false}) => Uri.parse(stream
      ? '$_base/$model:streamGenerateContent?alt=sse'
      : '$_base/$model:generateContent');

  static Map<String, String> headers(String key) => {
        'Content-Type': 'application/json',
        'x-goog-api-key': key,
      };

  /// True when trying the next attempt could help.
  static bool isRetryable(int status) =>
      status == 429 || status == 404 || status >= 500;

  /// Removes the Google Search tool from a request body. Used to retry when
  /// a model refuses the request because of search grounding.
  static String withoutSearch(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      m.remove('tools');
      return jsonEncode(m);
    } catch (_) {
      return body;
    }
  }

  static bool _usesSearch(String body) => body.contains('google_search');

  /// Normal (non-streaming) call with fallback. Returns the last response
  /// if every attempt failed, so the caller can read the status.
  static Future<http.Response> post(String body) async {
    final res = await _postOnce(body);
    if (res.statusCode == 400 && _usesSearch(body)) {
      return _postOnce(withoutSearch(body));
    }
    return res;
  }

  static Future<http.Response> _postOnce(String body) async {
    http.Response? last;
    for (final a in attempts()) {
      http.Response res;
      try {
        res = await http
            .post(url(a.model), headers: headers(a.key), body: body)
            .timeout(const Duration(seconds: 25));
      } on TimeoutException {
        continue;
      }
      last = res;
      if (res.statusCode == 200 || !isRetryable(res.statusCode)) return res;
      if (res.statusCode == 429) _markFailed(a.model, a.key);
    }
    if (last == null) throw Exception('Gemini request timed out.');
    return last;
  }

  /// Streaming call with fallback. The caller owns [client] and must close
  /// it. Returns the first response that is not a retryable error.
  static Future<http.StreamedResponse> openStream(
      http.Client client, String body) async {
    final res = await _openStreamOnce(client, body);
    if (res.statusCode == 400 && _usesSearch(body)) {
      await res.stream.drain<void>();
      return _openStreamOnce(client, withoutSearch(body));
    }
    return res;
  }

  static Future<http.StreamedResponse> _openStreamOnce(
      http.Client client, String body) async {
    http.StreamedResponse? last;
    for (final a in attempts()) {
      final req = http.Request('POST', url(a.model, stream: true))
        ..headers.addAll(headers(a.key))
        ..body = body;
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        continue;
      }
      if (res.statusCode == 200 || !isRetryable(res.statusCode)) return res;
      if (res.statusCode == 429) _markFailed(a.model, a.key);
      last = res;
      await res.stream.drain<void>();
    }
    if (last == null) throw Exception('Gemini request timed out.');
    return last;
  }

  /// Turns any error into one short, friendly sentence.
  static String friendly(Object error) {
    final e = error.toString();
    if (e.contains(noKeyMarker)) {
      return 'No Gemini key yet, Boss. Open the menu, tap Settings and paste '
          'your key.';
    }
    if (e.contains('429') || e.contains('RESOURCE_EXHAUSTED')) {
      return "I've hit today's free Gemini limit, Boss. Wait a bit, or add a "
          'backup key from another Google account in Settings.';
    }
    if (e.contains('API_KEY_INVALID') ||
        e.contains('(401') ||
        e.contains('(403') ||
        e.contains('API key not valid')) {
      return 'The AI service rejected the key, Boss. Check it in Settings.';
    }
    if (e.contains('(500') ||
        e.contains('(502') ||
        e.contains('(503') ||
        e.contains('(504')) {
      return 'Gemini is having a bad moment, Boss. Try again in a minute.';
    }
    if (error is SocketException ||
        e.contains('SocketException') ||
        e.contains('ClientException') ||
        e.contains('TimeoutException') ||
        e.contains('timed out')) {
      return "I can't reach the internet, Boss. Check your connection.";
    }
    final detail = e.replaceAll('Exception: ', '').replaceAll('\n', ' ');
    final short = detail.length > 140 ? detail.substring(0, 140) : detail;
    return 'Something went wrong on my end, Boss. Try again.\n($short)';
  }
}
