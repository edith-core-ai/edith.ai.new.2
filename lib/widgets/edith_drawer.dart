import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import '../theme/edith_theme.dart';

/// One tool shortcut in the drawer (God Screen, Builder, ...).
class DrawerFeature {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const DrawerFeature({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Left side menu, like Claude / ChatGPT / Gemini:
/// New chat, search, chat history by day, a short tools list, and the
/// profile + Settings row at the bottom.
class EdithDrawer extends StatefulWidget {
  final List<ChatThread> threads;
  final String? activeThreadId;
  final List<DrawerFeature> features;
  final String profileName;
  final VoidCallback onNewChat;
  final void Function(ChatThread thread) onSelect;
  final void Function(ChatThread thread) onRename;
  final void Function(ChatThread thread) onDelete;
  final VoidCallback onSettings;

  const EdithDrawer({
    super.key,
    required this.threads,
    required this.activeThreadId,
    required this.features,
    required this.profileName,
    required this.onNewChat,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onSettings,
  });

  @override
  State<EdithDrawer> createState() => _EdithDrawerState();
}

class _EdithDrawerState extends State<EdithDrawer> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _groupOf(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff <= 7) return 'Previous 7 days';
    return 'Older';
  }

  static const _order = ['Today', 'Yesterday', 'Previous 7 days', 'Older'];

  /// Threads that match the search, minus empty "New Chat" leftovers
  /// (except the chat that is open right now).
  List<ChatThread> _visible() {
    final q = _query.trim().toLowerCase();
    return widget.threads.where((t) {
      final empty = t.title == 'New Chat' && t.preview.isEmpty;
      if (empty && t.id != widget.activeThreadId) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.preview.toLowerCase().contains(q);
    }).toList();
  }

  void _menuFor(ChatThread t) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onRename(t);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onDelete(t);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threads = _visible();
    final groups = <String, List<ChatThread>>{};
    for (final t in threads) {
      groups.putIfAbsent(_groupOf(t.updatedAt), () => []).add(t);
    }

    return Drawer(
      width: 310,
      child: SafeArea(
        child: Column(
          children: [
            // Top: New chat + search.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  InkWell(
                    onTap: widget.onNewChat,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: EdithTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_square,
                              size: 20, color: EdithTheme.electricBlue),
                          SizedBox(width: 12),
                          Text('New chat',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search chats',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: EdithTheme.textSecondary),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),

            // Middle: history (scrolls) + tools.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                children: [
                  if (threads.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No chats yet.',
                        style: TextStyle(color: EdithTheme.textSecondary),
                      ),
                    ),
                  for (final name in _order)
                    if (groups[name] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: EdithTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final t in groups[name]!) _threadTile(t),
                    ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 22, 12, 8),
                    child: Text(
                      'Tools',
                      style: TextStyle(
                        color: EdithTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in widget.features) _featureChip(f),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom: profile + settings.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: EdithTheme.surfaceHigh,
                    child: Text(
                      widget.profileName.isEmpty
                          ? '?'
                          : widget.profileName[0].toUpperCase(),
                      style: TextStyle(
                        color: EdithTheme.electricBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.profileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: widget.onSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _threadTile(ChatThread t) {
    final active = t.id == widget.activeThreadId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? EdithTheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onSelect(t),
          onLongPress: () => _menuFor(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz,
                      size: 18, color: EdithTheme.textSecondary),
                  tooltip: 'Chat options',
                  onPressed: () => _menuFor(t),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureChip(DrawerFeature f) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        // Close the drawer first, then open the tool.
        Navigator.pop(context);
        f.onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: EdithTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(f.icon, size: 18, color: EdithTheme.electricBlue),
            const SizedBox(width: 8),
            Text(f.label, style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}
