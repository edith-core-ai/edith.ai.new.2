import 'package:flutter/material.dart';
import '../brains/memory_brain.dart';
import '../brains/memory_core.dart';
import '../services/edith_prefs.dart';
import '../services/proactive_service.dart';
import '../services/reflection_service.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

/// Presence: the three things that make her feel alive.
///  1. Live voice: a real-time call, she stops when you interrupt.
///  2. Messages from her: morning, evening, follow-ups, reminders.
///  3. Learning: she reads each chat and keeps what matters.
class PresenceScreen extends StatefulWidget {
  const PresenceScreen({super.key});

  @override
  State<PresenceScreen> createState() => _PresenceScreenState();
}

class _PresenceScreenState extends State<PresenceScreen> {
  late final TextEditingController _modelController;
  List<ScheduledItem> _items = [];
  bool _exact = true;
  bool _learning = false;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: EdithPrefs.liveModel);
    _reload();
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await ProactiveService.list();
    final exact = await ProactiveService.canExact();
    if (!mounted) return;
    setState(() {
      _items = items;
      _exact = exact;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  // ───────────── live voice ─────────────

  Future<void> _saveModel() async {
    await EdithPrefs.setLiveModel(_modelController.text);
    _modelController.text = EdithPrefs.liveModel;
    _snack('Live model saved.');
  }

  // ───────────── messages from her ─────────────

  Future<void> _toggleProactive(bool on) async {
    if (on) {
      final ok = await ProactiveService.ensurePermission();
      if (!ok) {
        _snack('Notifications are off for EDITH. Turn them on in phone '
            'Settings, then try again.');
        return;
      }
      await EdithPrefs.setProactive(true);
      await ProactiveService.refreshDaily(force: true);
    } else {
      await EdithPrefs.setProactive(false);
      await ProactiveService.refreshDaily();
    }
    await _reload();
    if (mounted) setState(() {});
  }

  Future<void> _pickTime(bool morning) async {
    final cur =
        morning ? EdithPrefs.morningMinutes : EdithPrefs.eveningMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t == null) return;
    final minutes = t.hour * 60 + t.minute;
    if (morning) {
      await EdithPrefs.setMorningMinutes(minutes);
    } else {
      await EdithPrefs.setEveningMinutes(minutes);
    }
    await ProactiveService.refreshDaily();
    await _reload();
    if (mounted) setState(() {});
  }

  Future<void> _sendTest() async {
    if (!await ProactiveService.ensurePermission()) {
      _snack('Notifications are off for EDITH. Turn them on in phone Settings.');
      return;
    }
    final r = await ProactiveService.schedule(
      id: 9099,
      at: DateTime.now().add(const Duration(seconds: 10)),
      text: 'Test, Boss. This is how I will reach you.',
    );
    _snack(r == null
        ? 'Could not schedule the test.'
        : 'Test message coming in about 10 seconds. Close the app to see it '
            'arrive.');
    await _reload();
  }

  // ───────────── learning ─────────────

  Future<void> _learnNow() async {
    setState(() => _learning = true);
    var facts = 0;
    var lessons = 0;
    var followUps = 0;
    try {
      final brain = MemoryBrain();
      final threads = await brain.loadThreads();
      for (final t in threads.take(3)) {
        final msgs = await brain.loadMessages(t.id);
        final r = await ReflectionService.reflect(t.id, msgs, force: true);
        facts += r.facts;
        lessons += r.lessons;
        followUps += r.followUps;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _learning = false);
    _snack(facts + lessons + followUps == 0
        ? 'Nothing new to learn from your latest chats.'
        : 'Learned $facts fact(s). $lessons rule(s) wait for your approval. '
            '$followUps follow-up(s) planned.');
  }

  // ───────────── build ─────────────

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: EdithTheme.electricBlue,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
              color: EdithTheme.textSecondary, fontSize: 13, height: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final proactive = EdithPrefs.proactive;
    return Scaffold(
      appBar: AppBar(title: const Text('Presence')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _title('Live voice'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Real-time call'),
            subtitle: const Text(
                'The mic button starts a live call with Gemini. You can '
                'interrupt her. If it cannot connect, the normal voice is '
                'used.'),
            value: EdithPrefs.liveVoice,
            onChanged: (v) async {
              await EdithPrefs.setLiveVoice(v);
              if (mounted) setState(() {});
            },
          ),
          if (EdithPrefs.liveVoice) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute my mic while she talks'),
              subtitle: const Text(
                  'Turn on if she hears herself on the speaker. You will not '
                  'be able to interrupt her by voice.'),
              value: EdithPrefs.halfDuplex,
              onChanged: (v) async {
                await EdithPrefs.setHalfDuplex(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Live model',
                hintText: EdithPrefs.defaultLiveModel,
              ),
              onSubmitted: (_) => _saveModel(),
              onEditingComplete: _saveModel,
            ),
            _hint('Google renames live models often. If calls fail to start, '
                'check the current name at ai.google.dev and paste it here. '
                'Her voice is chosen in Settings, Voice.'),
          ],
          _title('Messages from her'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('She messages first'),
            subtitle: const Text(
                'A morning message, an evening check-in, and follow-ups on '
                'things you told her about. Needs notifications.'),
            value: proactive,
            onChanged: _toggleProactive,
          ),
          if (proactive) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Morning message'),
              subtitle: Text(_time(EdithPrefs.morningMinutes)),
              value: EdithPrefs.morningOn,
              onChanged: (v) async {
                await EdithPrefs.setMorningOn(v);
                await ProactiveService.refreshDaily();
                await _reload();
                if (mounted) setState(() {});
              },
            ),
            if (EdithPrefs.morningOn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Change morning time'),
                onTap: () => _pickTime(true),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Evening check-in'),
              subtitle: Text(_time(EdithPrefs.eveningMinutes)),
              value: EdithPrefs.eveningOn,
              onChanged: (v) async {
                await EdithPrefs.setEveningOn(v);
                await ProactiveService.refreshDaily();
                await _reload();
                if (mounted) setState(() {});
              },
            ),
            if (EdithPrefs.eveningOn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Change evening time'),
                onTap: () => _pickTime(false),
              ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test message'),
            subtitle: const Text('Arrives in about 10 seconds'),
            onTap: _sendTest,
          ),
          if (!_exact)
            _hint('Your phone only allows approximate alarms for EDITH, so '
                'messages can arrive a few minutes late. In phone Settings, '
                'Apps, EDITH, allow "Alarms & reminders" for exact timing.'),
          _title('Waiting to be sent (${_items.length})'),
          if (_items.isEmpty)
            _hint('Nothing scheduled. Ask her: "remind me at 5 pm to call '
                'mum".'),
          for (final i in _items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                i.kind == 'reminder'
                    ? Icons.alarm
                    : Icons.chat_bubble_outline,
                color: EdithTheme.textSecondary,
              ),
              title: Text(i.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${i.at.toString().substring(0, 16)}${i.daily ? ' · every day' : ''}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: EdithTheme.textSecondary),
                onPressed: () async {
                  await ProactiveService.cancel(i.id);
                  await _reload();
                },
              ),
            ),
          _title('Learning'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Learn after each chat'),
            subtitle: const Text(
                'When you leave a chat she keeps lasting facts about you and '
                'a one-line note of what you talked about. She may suggest '
                'rules for herself, which you approve in Self-improvement.'),
            value: EdithPrefs.autoLearn,
            onChanged: (v) async {
              await EdithPrefs.setAutoLearn(v);
              if (mounted) setState(() {});
            },
          ),
          _hint('Now: ${SettingsService.memories.length} facts, '
              '${MemoryCore.digests.length} chat notes, '
              '${MemoryCore.pendingLessons.length} rule(s) waiting for you. '
              'See and delete them in Memory and Self-improvement.'),
          ElevatedButton.icon(
            onPressed: _learning ? null : _learnNow,
            icon: _learning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.school_outlined),
            label: Text(_learning ? 'Reading…' : 'Learn from my latest chats now'),
          ),
        ],
      ),
    );
  }
}
