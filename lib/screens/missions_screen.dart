import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/mission.dart';
import '../brains/missions_brain.dart';
import '../theme/edith_theme.dart';

/// Missions screen — v0.4 (Strategy piece).
/// Track goals/projects. EDITH doesn't auto-generate these yet — that
/// (her proactively recommending missions based on conversation) is a
/// later refinement once she has more context to work from.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  final _brain = MissionsBrain();
  final _uuid = const Uuid();
  List<Mission> _missions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final missions = await _brain.loadMissions();
    setState(() {
      _missions = missions;
      _loading = false;
    });
  }

  Future<void> _addMission() async {
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EdithTheme.surface,
        title: Text('New Mission', style: TextStyle(color: EdithTheme.electricBlue)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: EdithTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Mission title',
                hintStyle: TextStyle(color: EdithTheme.textSecondary),
              ),
            ),
            TextField(
              controller: notesController,
              style: const TextStyle(color: EdithTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Notes (optional)',
                hintStyle: TextStyle(color: EdithTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: EdithTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Add', style: TextStyle(color: EdithTheme.electricBlue)),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.trim().isNotEmpty) {
      final mission = Mission(
        id: _uuid.v4(),
        title: titleController.text.trim(),
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        createdAt: DateTime.now(),
      );
      await _brain.addMission(mission);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _missions.where((m) => !m.completed).toList();
    final completed = _missions.where((m) => m.completed).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MISSIONS',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: EdithTheme.electricBlue,
        foregroundColor: Colors.black,
        onPressed: _addMission,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: EdithTheme.electricBlue),
            )
          : _missions.isEmpty
              ? const Center(
                  child: Text(
                    'NO ACTIVE MISSIONS',
                    style: TextStyle(color: EdithTheme.textSecondary, letterSpacing: 4),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (active.isNotEmpty) ...[
                      const _SectionLabel('ACTIVE'),
                      ...active.map((m) => _MissionTile(
                            mission: m,
                            onToggle: () async {
                              await _brain.toggleComplete(m.id);
                              _load();
                            },
                            onDelete: () async {
                              await _brain.deleteMission(m.id);
                              _load();
                            },
                          )),
                    ],
                    if (completed.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const _SectionLabel('COMPLETED'),
                      ...completed.map((m) => _MissionTile(
                            mission: m,
                            onToggle: () async {
                              await _brain.toggleComplete(m.id);
                              _load();
                            },
                            onDelete: () async {
                              await _brain.deleteMission(m.id);
                              _load();
                            },
                          )),
                    ],
                  ],
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: EdithTheme.electricBlue,
          letterSpacing: 2,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  final Mission mission;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _MissionTile({
    required this.mission,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: EdithTheme.surface,
        border: Border.all(color: EdithTheme.electricBlue.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              mission.completed ? Icons.check_circle : Icons.radio_button_unchecked,
              color: EdithTheme.electricBlue,
            ),
            onPressed: onToggle,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  style: TextStyle(
                    color: mission.completed
                        ? EdithTheme.textSecondary
                        : EdithTheme.textPrimary,
                    decoration: mission.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (mission.notes != null)
                  Text(
                    mission.notes!,
                    style: const TextStyle(color: EdithTheme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: EdithTheme.textSecondary, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
