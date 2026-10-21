import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/edith_theme.dart';

/// What EDITH remembers about you between chats. Add, read, delete.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<String> _items = [];
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(SettingsService.memories);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await SettingsService.addMemory(text);
    _controller.clear();
    setState(() => _items = List<String>.from(SettingsService.memories));
  }

  Future<void> _remove(int i) async {
    await SettingsService.removeMemoryAt(i);
    setState(() => _items = List<String>.from(SettingsService.memories));
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget everything?'),
        content: const Text('All saved memories will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    await SettingsService.clearMemories();
    setState(() => _items = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(onPressed: _clearAll, child: const Text('Clear all')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: const Text(
              'Things EDITH remembers about you in every chat. She adds to '
              'this when you tell her something lasting or say "remember '
              'this". You can add or delete items here.',
              style: TextStyle(
                  color: EdithTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text('Nothing saved yet',
                        style: TextStyle(color: EdithTheme.textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_items[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close,
                            color: EdithTheme.textSecondary),
                        onPressed: () => _remove(i),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration:
                        const InputDecoration(hintText: 'Add something to remember'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle, color: EdithTheme.electricBlue),
                  onPressed: _add,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
