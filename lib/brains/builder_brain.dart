import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/build_project.dart';

/// Builder Brain — v0.5 (early piece).
/// EDITH generates a concrete plan (materials, steps, tips) for whatever
/// you want to build, and keeps a local library of past projects.
class BuilderBrain {
  static const _key = 'edith_build_projects';

  Future<List<BuildProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => BuildProject.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProject(BuildProject project) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(project.toJson()));
    await prefs.setStringList(_key, raw);
  }

  Future<void> deleteProject(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      projects.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
