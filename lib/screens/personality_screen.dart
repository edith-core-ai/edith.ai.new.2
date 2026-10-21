import 'package:flutter/material.dart';
import '../brains/edith_persona.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

/// Edit EDITH's instructions. Two parts, both fully editable:
///  - Character: who she is and how she talks.
///  - Rules: how she thinks, uses tools, checks her work and stays honest.
/// Her real safety locks (the Allow/Cancel dialog before messages and phone
/// control) are in the app code, so editing these texts cannot switch them off.
class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({super.key});

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  late final TextEditingController _character;
  late final TextEditingController _rules;

  @override
  void initState() {
    super.initState();
    _character = TextEditingController(text: edithCharacter);
    _rules = TextEditingController(text: edithRules);
  }

  @override
  void dispose() {
    _character.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _character.text.trim();
    final r = _rules.text.trim();
    // Saving the untouched original just clears the custom version.
    await SettingsService.setPersonaText(
        c == edithDefaultCharacter.trim() ? '' : c);
    await SettingsService.setRulesText(r == edithDefaultRules.trim() ? '' : r);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Saved. Applies to your next message.')),
    );
    Navigator.pop(context);
  }

  Future<void> _reset(bool character) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Back to the original?'),
        content: Text(character
            ? 'Your edited character will be replaced.'
            : 'Your edited rules will be replaced.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (character) {
      await SettingsService.setPersonaText('');
    } else {
      await SettingsService.setRulesText('');
    }
    if (!mounted) return;
    setState(() {
      if (character) {
        _character.text = edithDefaultCharacter;
      } else {
        _rules.text = edithDefaultRules;
      }
    });
  }

  Widget _editor({
    required String help,
    required TextEditingController controller,
    required bool isCharacter,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            help,
            style: const TextStyle(
              color: EdithTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                color: EdithTheme.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                fillColor: EdithTheme.surface,
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => _reset(isCharacter),
                child: const Text('Reset to original'),
              ),
              const Spacer(),
            ],
          ),
          ElevatedButton(onPressed: _save, child: const Text('Save both')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Personality'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Character'), Tab(text: 'Rules')],
          ),
        ),
        body: TabBarView(
          children: [
            _editor(
              help: 'Who EDITH is and how she talks: her name for you, her '
                  'tone, humour, and how short or long she answers.',
              controller: _character,
              isCharacter: true,
            ),
            _editor(
              help: 'How she thinks, when she uses tools, how she checks her '
                  'answers, and what she will not do. You can edit all of it. '
                  'The Allow/Cancel dialog before messages and phone control '
                  'is built into the app and stays on.',
              controller: _rules,
              isCharacter: false,
            ),
          ],
        ),
      ),
    );
  }
}
