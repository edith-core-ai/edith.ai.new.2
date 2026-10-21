import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/build_project.dart';
import '../brains/builder_brain.dart';
import '../services/gemini_endpoints.dart';
import '../services/gemini_service.dart';
import '../theme/edith_theme.dart';

/// Builder screen — v0.5 (early piece).
/// Describe something you want to build; EDITH generates a concrete
/// plan (materials, steps, tips). Saved locally as a project library.
class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  final _brain = BuilderBrain();
  final _gemini = GeminiService();
  final _uuid = const Uuid();
  final _inputController = TextEditingController();

  List<BuildProject> _projects = [];
  bool _generating = false;
  BuildProject? _viewing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await _brain.loadProjects();
    setState(() => _projects = projects);
  }

  Future<void> _generate() async {
    final idea = _inputController.text.trim();
    if (idea.isEmpty || _generating) return;

    setState(() => _generating = true);

    final prompt =
        'Generate a concrete build plan for: "$idea". '
        'Structure it clearly with these sections: Materials/Parts Needed, '
        'Step-by-Step Instructions (numbered), and Tips/Warnings. '
        'Be specific and practical, not generic.';

    try {
      final plan = await _gemini.ask(prompt, []);
      final project = BuildProject(
        id: _uuid.v4(),
        title: idea,
        plan: plan,
        createdAt: DateTime.now(),
      );
      await _brain.saveProject(project);
      _inputController.clear();
      await _load();
      if (mounted) setState(() => _viewing = project);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: EdithTheme.surface,
            content: Text(
              GeminiEndpoints.friendly(e),
              style: TextStyle(color: EdithTheme.electricBlue),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BUILDER',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold),
        ),
        leading: _viewing != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _viewing = null),
              )
            : null,
      ),
      body: _viewing != null ? _buildPlanView() : _buildListView(),
    );
  }

  Widget _buildPlanView() {
    final project = _viewing!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.title,
            style: TextStyle(
              color: EdithTheme.electricBlue,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            project.plan,
            style: const TextStyle(color: EdithTheme.textPrimary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _inputController,
                maxLines: 2,
                style: const TextStyle(color: EdithTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'What do you want to build?',
                  hintStyle: const TextStyle(color: EdithTheme.textSecondary),
                  filled: true,
                  fillColor: EdithTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: EdithTheme.electricBlue.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _generating ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EdithTheme.electricBlue,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_generating ? 'Generating…' : 'Generate Plan'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _projects.isEmpty
              ? const Center(
                  child: Text(
                    'NO PROJECTS YET',
                    style: TextStyle(color: EdithTheme.textSecondary, letterSpacing: 4),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _projects.length,
                  itemBuilder: (context, i) {
                    final project = _projects[_projects.length - 1 - i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: EdithTheme.surface,
                        border: Border.all(
                            color: EdithTheme.electricBlue.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListTile(
                        title: Text(project.title,
                            style: const TextStyle(color: EdithTheme.textPrimary)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close,
                              color: EdithTheme.textSecondary, size: 18),
                          onPressed: () async {
                            await _brain.deleteProject(project.id);
                            _load();
                          },
                        ),
                        onTap: () => setState(() => _viewing = project),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
