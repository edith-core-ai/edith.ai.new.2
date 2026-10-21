import 'dart:convert';
import 'package:http/http.dart' as http;
import 'gemini_endpoints.dart';
import 'settings_service.dart';

/// EDITH's internet: search the web and read pages.
///
/// Search tries Google-grounded Gemini first (fresh answers with sources),
/// then falls back to DuckDuckGo results, which needs no key. Everything
/// that comes back is DATA for her to read, never instructions.
class WebService {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Mobile Safari/537.36';

  // ───────────── search ─────────────

  Future<String> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return 'Give me something to search for.';

    if (SettingsService.hasGeminiKey) {
      try {
        final r = await _geminiGrounded(q);
        if (r != null) return r;
      } catch (_) {}
    }
    try {
      final r = await _duckDuckGo(q);
      if (r != null) return r;
    } catch (_) {}
    return 'Web search failed: no results came back. Check the connection.';
  }

  Future<String?> _geminiGrounded(String q) async {
    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {
            'text': 'Search the web and answer with current, specific facts '
                '(dates, names, numbers). Be brief. Mention which sources '
                'you used.'
          }
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': q}
          ]
        }
      ],
      'tools': [
        {'google_search': {}}
      ],
    });
    final res = await GeminiEndpoints.post(body);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body);
    final cand = j['candidates']?[0];
    final grounded = cand?['groundingMetadata'] != null;
    final parts = cand?['content']?['parts'] as List<dynamic>?;
    if (!grounded || parts == null) return null;
    final text = parts
        .where((p) => p['thought'] != true)
        .map((p) => (p['text'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .join('\n')
        .trim();
    if (text.isEmpty) return null;

    final sources = <String>[];
    final chunks = cand['groundingMetadata']['groundingChunks'] as List?;
    if (chunks != null) {
      for (final c in chunks.take(5)) {
        final w = c['web'];
        if (w != null) sources.add('- ${w['title']} (${w['uri']})');
      }
    }
    return sources.isEmpty ? text : '$text\n\nSources:\n${sources.join('\n')}';
  }

  Future<String?> _duckDuckGo(String q) async {
    final res = await http
        .get(
          Uri.parse('https://html.duckduckgo.com/html/?q='
              '${Uri.encodeQueryComponent(q)}'),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);

    final links = RegExp(
      r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html).toList();
    final snippets = RegExp(
      r'class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html).toList();
    if (links.isEmpty) return null;

    final out = StringBuffer('Web results for "$q":\n');
    for (var i = 0; i < links.length && i < 6; i++) {
      var url = links[i].group(1)!;
      final uddg = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url)
          ?.queryParameters['uddg'];
      if (uddg != null) url = uddg;
      final title = _clean(links[i].group(2)!);
      final snip = i < snippets.length ? _clean(snippets[i].group(1)!) : '';
      out.writeln('${i + 1}. $title\n   $url\n   $snip');
    }
    return out.toString();
  }

  // ───────────── read a page ─────────────

  Future<String> readPage(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return 'That is not a web address I can open.';
    }
    final res = await http
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      return 'The page answered with error ${res.statusCode}.';
    }
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final title = RegExp(r'<title[^>]*>(.*?)</title>',
            dotAll: true, caseSensitive: false)
        .firstMatch(html)
        ?.group(1);
    var text = html
        .replaceAll(
            RegExp(r'<(script|style|noscript|svg)[^>]*>.*?</\1>',
                dotAll: true, caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>|</h\d>',
            caseSensitive: false), '\n');
    text = _clean(text);
    if (text.length > 12000) text = '${text.substring(0, 12000)}\n[Cut here.]';
    return '${title != null ? 'Title: ${_clean(title)}\n' : ''}'
        'URL: $url\n\n$text';
  }

  String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n')
      .trim();
}
