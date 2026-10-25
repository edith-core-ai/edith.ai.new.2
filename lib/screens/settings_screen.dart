import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../brains/memory_brain.dart';
import '../services/gemini_tts_service.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';
import 'memory_screen.dart';
import 'self_improve_screen.dart';
import 'personality_screen.dart';
import 'presence_screen.dart';

/// Settings — grouped cards: AI, Voice, Tools, Phone control.
///
/// Keys live only on this phone (SettingsService / SharedPreferences).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _geminiController;
  late final TextEditingController _geminiBackupController;
  late final TextEditingController _grokController;
  late final TextEditingController _grokModelController;
  late bool _preferGrok;
  late final TextEditingController _windyController;
  late bool _useGeminiVoice;
  late String _geminiVoice;
  late final TextEditingController _elevenController;
  late final TextEditingController _voiceIdController;
  late final TextEditingController _weatherController;
  late final TextEditingController _newsController;
  late bool _autoSpeak;
  late bool _useElevenLabs;
  late bool _wakeWord;

  @override
  void initState() {
    super.initState();
    _geminiController = TextEditingController(
      text: SettingsService.hasGeminiKey ? SettingsService.geminiApiKey : '',
    );
    _geminiBackupController =
        TextEditingController(text: SettingsService.geminiApiKeyBackup);
    _grokController = TextEditingController(text: SettingsService.grokApiKey);
    _grokModelController =
        TextEditingController(text: SettingsService.grokModel);
    _preferGrok = SettingsService.preferGrok;
    _windyController = TextEditingController(text: SettingsService.windyKey);
    _useGeminiVoice = SettingsService.useGeminiVoice;
    _geminiVoice = SettingsService.geminiVoice;
    _elevenController = TextEditingController(
      text: SettingsService.hasElevenLabsKey
          ? SettingsService.elevenLabsApiKey
          : '',
    );
    _voiceIdController = TextEditingController(
      text: SettingsService.elevenLabsVoiceId.startsWith('PASTE_')
          ? ''
          : SettingsService.elevenLabsVoiceId,
    );
    _weatherController =
        TextEditingController(text: SettingsService.openWeatherKey);
    _newsController = TextEditingController(text: SettingsService.newsApiKey);
    _autoSpeak = SettingsService.autoSpeak;
    _useElevenLabs = SettingsService.useElevenLabs;
    _wakeWord = SettingsService.wakeWordEnabled;
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _geminiBackupController.dispose();
    _grokController.dispose();
    _grokModelController.dispose();
    _windyController.dispose();
    _elevenController.dispose();
    _voiceIdController.dispose();
    _weatherController.dispose();
    _newsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await SettingsService.setGeminiApiKey(_geminiController.text);
    await SettingsService.setGeminiApiKeyBackup(_geminiBackupController.text);
    await SettingsService.setGrokApiKey(_grokController.text);
    await SettingsService.setGrokModel(_grokModelController.text);
    await SettingsService.setPreferGrok(_preferGrok);
    await SettingsService.setWindyKey(_windyController.text);
    await SettingsService.setUseGeminiVoice(_useGeminiVoice);
    await SettingsService.setGeminiVoice(_geminiVoice);
    await SettingsService.setElevenLabsApiKey(_elevenController.text);
    await SettingsService.setElevenLabsVoiceId(_voiceIdController.text);
    await SettingsService.setAutoSpeak(_autoSpeak);
    await SettingsService.setUseElevenLabs(_useElevenLabs);
    await SettingsService.setOpenWeatherKey(_weatherController.text);
    await SettingsService.setNewsApiKey(_newsController.text);
    await SettingsService.setWakeWordEnabled(_wakeWord);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved, Boss.')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _pickAccent(Color color) async {
    EdithTheme.setAccent(color);
    await SettingsService.setAccentColor(color);
    if (mounted) setState(() {});
  }

  Future<void> _openAndroidSettings(String action) async {
    try {
      await AndroidIntent(action: action).launch();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open that page. Open it from the phone's "
              'Settings app.'),
        ),
      );
    }
  }

  Future<void> _exportChats() async {
    final brain = MemoryBrain();
    final threads = await brain.loadThreads();
    final b = StringBuffer();
    for (final t in threads) {
      b.writeln('=== ${t.title} ===');
      final msgs = await brain.loadMessages(t.id);
      for (final m in msgs) {
        b.writeln('${m.role == 'user' ? 'Hilal' : 'EDITH'}: ${m.content}');
      }
      b.writeln();
    }
    if (b.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No chats yet.')));
      }
      return;
    }
    await Share.share(b.toString(), subject: 'EDITH chats');
  }

  Future<void> _deleteAllChats() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all chats?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final brain = MemoryBrain();
    for (final t in await brain.loadThreads()) {
      await brain.deleteThread(t.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All chats deleted. Reopen the chat list.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            title: 'Appearance',
            children: [
              const Text(
                'Theme colour',
                style: TextStyle(color: EdithTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in EdithTheme.accentChoices)
                    GestureDetector(
                      onTap: () => _pickAccent(c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: EdithTheme.accent.value.toARGB32() ==
                                    c.toARGB32()
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Data and about',
            children: [
              _ActionRow(
                icon: Icons.ios_share,
                title: 'Export all chats',
                subtitle: 'Share every conversation as one text file',
                onTap: _exportChats,
              ),
              _ActionRow(
                icon: Icons.delete_sweep_outlined,
                title: 'Delete all chats',
                subtitle: 'Removes every conversation from this phone',
                onTap: _deleteAllChats,
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline,
                    color: EdithTheme.textSecondary),
                title: Text('E.D.I.T.H.'),
                subtitle: Text(
                    'Eminent Digital Intelligence & Tactical Hegemon\n'
                    'Built by Hilal. Keys stay on this phone.'),
              ),
            ],
          ),
          _Section(
            title: 'Character',
            children: [
              _ActionRow(
                icon: Icons.psychology_outlined,
                title: 'Personality',
                subtitle: 'Edit how EDITH talks and acts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PersonalityScreen()),
                ),
              ),
              _ActionRow(
                icon: Icons.record_voice_over_outlined,
                title: 'Presence',
                subtitle: 'Live voice call, messages from her, learning',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PresenceScreen()),
                ),
              ),
              _ActionRow(
                icon: Icons.auto_fix_high,
                title: 'Self-improvement',
                subtitle: 'She reviews her mistakes and writes rules for herself',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SelfImproveScreen()),
                ),
              ),
              _ActionRow(
                icon: Icons.memory_outlined,
                title: 'Memory',
                subtitle: 'What she remembers about you',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryScreen()),
                ),
              ),
            ],
          ),
          _Section(
            title: 'AI',
            children: [
              _SecretField(
                controller: _geminiController,
                label: 'Gemini API key',
                hint: 'From aistudio.google.com/apikey',
              ),
              const SizedBox(height: 14),
              _SecretField(
                controller: _geminiBackupController,
                label: 'Backup Gemini key (optional)',
                hint: 'Must be from a different Google account',
              ),
              const SizedBox(height: 10),
              const _Hint(
                'Free limits belong to the Google account, not the key. A '
                'second key from the same account will not help.',
              ),
              const SizedBox(height: 18),
              _SecretField(
                controller: _grokController,
                label: 'Grok API key (optional)',
                hint: 'From console.x.ai',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _grokModelController,
                decoration: const InputDecoration(
                  labelText: 'Grok model',
                  hintText: 'grok-4.7',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Grok as main brain'),
                subtitle: const Text(
                    'Off: Gemini first, Grok takes over if Gemini fails'),
                value: _preferGrok,
                onChanged: (v) => setState(() => _preferGrok = v),
              ),
              const SizedBox(height: 10),
              _SecretField(
                controller: _windyController,
                label: 'Windy Webcams key (optional)',
                hint: 'Free, from api.windy.com. For the God Screen cameras',
              ),
            ],
          ),
          _Section(
            title: 'Voice',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Gemini voice'),
                subtitle: const Text(
                    'Her voice comes from Gemini. Needs your Gemini key.'),
                value: _useGeminiVoice,
                onChanged: (v) => setState(() => _useGeminiVoice = v),
              ),
              if (_useGeminiVoice)
                DropdownButtonFormField<String>(
                  value: GeminiTtsService.voices.contains(_geminiVoice)
                      ? _geminiVoice
                      : 'Kore',
                  decoration: const InputDecoration(labelText: 'Voice'),
                  items: [
                    for (final v in GeminiTtsService.voices)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => setState(() => _geminiVoice = v ?? 'Kore'),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read replies aloud'),
                subtitle: const Text('Uses the free voice on your phone'),
                value: _autoSpeak,
                onChanged: (v) => setState(() => _autoSpeak = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use ElevenLabs voice'),
                subtitle: const Text('Better sound, limited free credits'),
                value: _useElevenLabs,
                onChanged: (v) => setState(() => _useElevenLabs = v),
              ),
              if (_useElevenLabs) ...[
                const SizedBox(height: 8),
                _SecretField(
                  controller: _elevenController,
                  label: 'ElevenLabs API key',
                  hint: 'elevenlabs.io → Profile → API Keys',
                ),
                const SizedBox(height: 14),
                _PlainField(
                  controller: _voiceIdController,
                  label: 'ElevenLabs voice ID',
                  hint: 'From the voice menu in Voice Lab',
                ),
              ],
            ],
          ),
          _Section(
            title: 'Tools',
            children: [
              _SecretField(
                controller: _weatherController,
                label: 'OpenWeather key',
                hint: 'openweathermap.org/api',
              ),
              const SizedBox(height: 14),
              _SecretField(
                controller: _newsController,
                label: 'NewsAPI key',
                hint: 'newsapi.org',
              ),
            ],
          ),
          _Section(
            title: 'Phone control',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wake word "EDITH"'),
                subtitle: const Text('Say "EDITH" to open voice chat. Needs the microphone.'),
                value: _wakeWord,
                onChanged: (v) => setState(() => _wakeWord = v),
              ),
              _ActionRow(
                icon: Icons.accessibility_new,
                title: 'Phone control',
                subtitle: 'Let EDITH tap and type for you',
                onTap: () =>
                    _openAndroidSettings('android.settings.ACCESSIBILITY_SETTINGS'),
              ),
              _ActionRow(
                icon: Icons.notifications_none,
                title: 'Notification access',
                subtitle: 'Let EDITH read your notifications',
                onTap: () => _openAndroidSettings(
                    'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 14),
          const _Hint(
            'Keys are stored only on this phone. They are sent only to '
            'Google, ElevenLabs, OpenWeather and NewsAPI when you use those '
            'features.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: EdithTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EdithTheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecretField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _SecretField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: EdithTheme.textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        fillColor: EdithTheme.surfaceHigh,
        suffixIcon: IconButton(
          icon: Icon(
            _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: EdithTheme.textSecondary,
            size: 20,
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _PlainField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      style: const TextStyle(color: EdithTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        fillColor: EdithTheme.surfaceHigh,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: EdithTheme.electricBlue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right, color: EdithTheme.textSecondary),
      onTap: onTap,
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: EdithTheme.textSecondary,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}
