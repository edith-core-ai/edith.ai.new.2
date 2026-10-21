import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/gemini_service.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

class _Story {
  final String title;
  final String source;
  final String url;
  final String? image;
  final String blurb;
  String summary;
  bool liked = false;
  _Story(this.title, this.source, this.url, this.image, this.blurb)
      : summary = blurb;
}

/// News feed: picture, headline, short AI summary, source. Needs the
/// NewsAPI key from Settings.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _cats = ['general', 'technology', 'business', 'science', 'sports', 'health'];
  String _cat = 'general';
  List<_Story> _stories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = SettingsService.newsApiKey;
    if (key.isEmpty || key.startsWith('PASTE_')) {
      setState(() {
        _loading = false;
        _error = 'Add a NewsAPI key in Settings to see the feed.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await http
          .get(Uri.parse('https://newsapi.org/v2/top-headlines?country=us'
              '&category=$_cat&pageSize=15&apiKey=$key'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw Exception('News request failed (${r.statusCode}).');
      }
      final arts = (jsonDecode(r.body)['articles'] as List<dynamic>? ?? []);
      final list = <_Story>[];
      for (final a in arts) {
        final m = a as Map<String, dynamic>;
        final t = (m['title'] ?? '').toString();
        if (t.isEmpty || t == '[Removed]') continue;
        list.add(_Story(
          t,
          ((m['source'] as Map?)?['name'] ?? '').toString(),
          (m['url'] ?? '').toString(),
          m['urlToImage']?.toString(),
          (m['description'] ?? '').toString(),
        ));
      }
      if (!mounted) return;
      setState(() {
        _stories = list;
        _loading = false;
      });
      _summarize(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// One Gemini call writes a two-sentence summary for every story.
  Future<void> _summarize(List<_Story> list) async {
    if (list.isEmpty) return;
    final b = StringBuffer(
        'For each numbered news item write a plain two-sentence summary. '
        'Reply ONLY as lines "N|summary", one per item, no extra text.\n');
    for (var i = 0; i < list.length; i++) {
      b.writeln('${i + 1}. ${list[i].title} — ${list[i].blurb}');
    }
    try {
      final out = await GeminiService().ask(b.toString(), []);
      for (final line in out.split('\n')) {
        final p = line.indexOf('|');
        if (p < 1) continue;
        final n = int.tryParse(line.substring(0, p).trim());
        final s = line.substring(p + 1).trim();
        if (n != null && n >= 1 && n <= list.length && s.isNotEmpty) {
          list[n - 1].summary = s;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _load,
        child: const Icon(Icons.refresh),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in _cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                    child: ChoiceChip(
                      label: Text(c[0].toUpperCase() + c.substring(1)),
                      selected: _cat == c,
                      onSelected: (_) {
                        setState(() => _cat = c);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: EdithTheme.electricBlue))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: EdithTheme.textSecondary)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 90),
                        itemCount: _stories.length,
                        itemBuilder: (_, i) => _card(_stories[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _card(_Story s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.image != null)
            Image.network(
              s.image!,
              height: 210,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    style: const TextStyle(
                        color: EdithTheme.textPrimary,
                        fontSize: 22,
                        height: 1.25)),
                const SizedBox(height: 8),
                if (s.summary.isNotEmpty)
                  Text(s.summary,
                      style: const TextStyle(
                          color: EdithTheme.textPrimary,
                          fontSize: 16,
                          height: 1.4)),
                const SizedBox(height: 6),
                const Text('Generated with AI, which can make mistakes',
                    style: TextStyle(
                        color: EdithTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.auto_awesome, color: EdithTheme.electricBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.source,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: EdithTheme.textSecondary)),
              ),
              IconButton(
                icon: Icon(s.liked ? Icons.favorite : Icons.favorite_border,
                    color: s.liked ? Colors.redAccent : null),
                onPressed: () => setState(() => s.liked = !s.liked),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => Share.share('${s.title}\n${s.url}'),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(Uri.parse(s.url),
                    mode: LaunchMode.externalApplication),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
