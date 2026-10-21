import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mission.dart';

/// Missions Brain — v0.4 (Strategy piece).
///
/// Tracks goals/projects locally, same storage pattern as Memory Brain.
/// Pure software — works identically whether EDITH is a browser tab or
/// an installed app, unlike System Control (battery, SMS) which needs
/// a real installed app.
class MissionsBrain {
  static const _key = 'edith_missions';

  Future<List<Mission>> loadMissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => Mission.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAll(List<Mission> missions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      missions.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<void> addMission(Mission mission) async {
    final missions = await loadMissions();
    missions.add(mission);
    await _saveAll(missions);
  }

  Future<void> toggleComplete(String id) async {
    final missions = await loadMissions();
    final index = missions.indexWhere((m) => m.id == id);
    if (index == -1) return;
    missions[index].completed = !missions[index].completed;
    await _saveAll(missions);
  }

  Future<void> deleteMission(String id) async {
    final missions = await loadMissions();
    missions.removeWhere((m) => m.id == id);
    await _saveAll(missions);
  }
}
