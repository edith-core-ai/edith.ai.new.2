import 'package:flutter/material.dart';
import '../brains/memory_brain.dart';
import '../brains/memory_core.dart';
import '../services/gemini_service.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

/// EDITH reviews her own recent chats, finds where she was slow, wrong or
/// unhelpful, and proposes short rules for herself. Hilal approves each one;
/// approved lessons go into her instructions for every future message.
/// Phone-control failures are added as lessons automatically.
class SelfImproveScreen extends StatefulWidget {
  const SelfImproveScreen({super.key});
  @override
  State<SelfImproveScreen> createState() => _SelfImproveScreenState();
}

class _SelfImproveScreenState extends State<SelfImproveScreen> {
  List<String> _proposals = [];
  bool _busy = false;
  String? _note;

  Future<void> _reflect() async {
    setState(() {
      _busy = true;
      _note = null;
      _proposals = [];
    });
    try {
      final brain = MemoryBrain();
      final threads = await brain.loadThreads();
      final b = StringBuffer();
      for (final t in threads.take(4)) {
        final msgs = await brain.loadMessages(t.id);
        for (final m in msgs.reversed.take(12).toList().reversed) {
          final c = m.content.length > 300
              ? m.content.substring(0, 300)
              : m.content;
          b.writeln('${m.role == 'user' ? 'USER' : 'EDITH'}: $c');
        }
        b.writeln('---');
      }
      if (b.isEmpty) {
        setState(() {
          _busy = false;
          _note = 'No chats to learn from yet.';
        });
        return;
      }
      final known = SettingsService.lessons.map((e) => '- $e').join('\n');
      final out = await GeminiService().ask(
        'You are reviewing your own recent conversations with your user.\n'
        'Find real mistakes: wrong answers, ignored requests, repeated '
        'corrections, complaints, slow or unclear replies, tool failures.\n'
        'Write at most 5 NEW short rules (one line each, imperative) that '
        'would stop those mistakes. Only rules the conversations support. '
        'Do not repeat existing lessons. If nothing needs fixing, reply NONE.\n'
        'Reply ONLY as lines starting with "- ".\n\n'
        'EXISTING LESSONS:\n${known.isEmpty ? '(none)' : known}\n\n'
        'RECENT CONVERSATIONS:\n$b',
        [],
      );
      final lines = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('- '))
          .map((l) => l.substring(2).trim())
          .where((l) => l.isNotEmpty)
          .take(5)
          .toList();
      if (!mounted) return;
      setState(() {
        _proposals = lines;
        _busy = false;
        if (lines.isEmpty) _note = 'Nothing new to fix right now.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = 'Could not reflect: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessons = SettingsService.lessons;
    return Scaffold(
      appBar: AppBar(title: const Text('Self-improvement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'She reads her own recent chats, finds her mistakes and writes '
            'rules for herself. You approve each rule. Approved rules apply '
            'to every message. Failed phone tasks are added automatically.',
            style: TextStyle(color: EdithTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _busy ? null : _reflect,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high),
            label: Text(_busy ? 'Reflecting…' : 'Reflect now'),
          ),
          if (MemoryCore.pendingLessons.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('LEARNED FROM YOUR CHATS (approve?)',
                style: TextStyle(
                    color: EdithTheme.electricBlue,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
            for (final p in List<String>.from(MemoryCore.pendingLessons))
              Card(
                color: EdithTheme.surface,
                margin: const EdgeInsets.only(top: 10),
                child: ListTile(
                  title: Text(p,
                      style: const TextStyle(color: EdithTheme.textPrimary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.greenAccent),
                        onPressed: () async {
                          await SettingsService.addLesson(p);
                          await MemoryCore.removePendingLesson(p);
                          if (mounted) setState(() {});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () async {
                          await MemoryCore.removePendingLesson(p);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_note!,
                  style: const TextStyle(color: EdithTheme.textSecondary)),
            ),
          for (final p in _proposals)
            Card(
              color: EdithTheme.surface,
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                title: Text(p,
                    style: const TextStyle(color: EdithTheme.textPrimary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.greenAccent),
                      onPressed: () async {
                        await SettingsService.addLesson(p);
                        if (mounted) setState(() => _proposals.remove(p));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () => setState(() => _proposals.remove(p)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          Text('LESSONS IN USE (${lessons.length})',
              style: TextStyle(
                  color: EdithTheme.electricBlue,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          if (lessons.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('None yet.',
                  style: TextStyle(color: EdithTheme.textSecondary)),
            ),
          for (var i = 0; i < lessons.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(lessons[i],
                  style: const TextStyle(
                      color: EdithTheme.textPrimary, fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await SettingsService.removeLessonAt(i);
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}
